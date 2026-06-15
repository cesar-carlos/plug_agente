import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/rpc/sql_db_streaming_auto_policy.dart';
import 'package:plug_agente/application/rpc/sql_execute_result_mapper.dart';
import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/application/rpc/sql_rpc_negotiated_capabilities.dart';
import 'package:plug_agente/application/rpc/sql_rpc_stream_terminal_emitter.dart';
import 'package:plug_agente/application/rpc/sql_streaming_connection_string_resolver.dart';
import 'package:plug_agente/application/rpc/sql_streaming_coordinator.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/odbc_stream_columnar_wire_config.dart';
import 'package:plug_agente/core/config/odbc_stream_wire_only_config.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_streaming_constants.dart';
import 'package:plug_agente/core/utils/batch_odbc_timeout.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/query/prepared_query_execution.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/i_streaming_named_parameter_preparer.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:plug_agente/domain/streaming/streaming_column_metadata.dart';
import 'package:plug_agente/domain/streaming/streaming_wire_chunk.dart';
import 'package:plug_agente/domain/validation/sql_validator.dart';
import 'package:uuid/uuid.dart';

class SqlRpcDbStreamingExecutor {
  SqlRpcDbStreamingExecutor({
    required FeatureFlags featureFlags,
    required SqlRpcMethodHandlerSupport support,
    required SqlStreamingCoordinator sqlStreamingCoordinator,
    required SqlDbStreamingAutoPolicy autoPolicy,
    required SqlRpcStreamTerminalEmitter terminalEmitter,
    required Uuid uuid,
    required Duration sqlExecuteTotalBudget,
    required IStreamingNamedParameterPreparer streamingNamedParameterPreparer,
    ActiveConfigResolver? activeConfigResolver,
    IAgentConfigRepository? configRepository,
    IStreamingDatabaseGateway? streamingGateway,
    IRpcDispatchMetricsCollector? dispatchMetrics,
    IOdbcConnectionSettings? odbcConnectionSettings,
  }) : _featureFlags = featureFlags,
       _support = support,
       _sqlStreamingCoordinator = sqlStreamingCoordinator,
       _autoPolicy = autoPolicy,
       _terminalEmitter = terminalEmitter,
       _uuid = uuid,
       _sqlExecuteTotalBudget = sqlExecuteTotalBudget,
       _activeConfigResolver = activeConfigResolver,
       _configRepository = configRepository,
       _streamingGateway = streamingGateway,
       _dispatchMetrics = dispatchMetrics,
       _odbcConnectionSettings = odbcConnectionSettings,
       _streamingNamedParameterPreparer = streamingNamedParameterPreparer;

  final FeatureFlags _featureFlags;
  final SqlRpcMethodHandlerSupport _support;
  final SqlStreamingCoordinator _sqlStreamingCoordinator;
  final SqlDbStreamingAutoPolicy _autoPolicy;
  final SqlRpcStreamTerminalEmitter _terminalEmitter;
  final Uuid _uuid;
  final Duration _sqlExecuteTotalBudget;
  final ActiveConfigResolver? _activeConfigResolver;
  final IAgentConfigRepository? _configRepository;
  final IStreamingDatabaseGateway? _streamingGateway;
  final IRpcDispatchMetricsCollector? _dispatchMetrics;
  final IOdbcConnectionSettings? _odbcConnectionSettings;
  final IStreamingNamedParameterPreparer _streamingNamedParameterPreparer;

  /// Tries to stream directly from DB when enabled. Returns null to fall back.
  Future<RpcResponse?> tryStreamingFromDb(
    RpcRequest request,
    QueryRequest queryRequest,
    String sql,
    IRpcStreamEmitter? streamEmitter, {
    required TransportLimits limits,
    required DateTime? deadline,
    required int timeoutMs,
    required Map<String, dynamic> negotiatedExtensions,
    required bool preferDbStreaming,
    required int effectiveMaxRows,
    String? clientToken,
    String? database,
  }) async {
    final normalizedSql = _autoPolicy.normalizeSqlForDbStreaming(sql);
    final autoStreamingReason = _autoPolicy.resolveAutoReason(
      featureFlags: _featureFlags,
      queryRequest: queryRequest,
      sql: sql,
      negotiatedExtensions: negotiatedExtensions,
      preferDbStreaming: preferDbStreaming,
      effectiveMaxRows: effectiveMaxRows,
      limits: limits,
    );
    final autoStreaming = autoStreamingReason != DbStreamingAutoReason.none;
    if (!supportsStreamingChunks(negotiatedExtensions)) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('streaming_chunks_not_negotiated');
      return null;
    }
    if (request.isNotification) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('notification_request');
      return null;
    }
    if (!_featureFlags.enableSocketStreamingFromDb ||
        (!_featureFlags.enableSocketStreamingChunks && !autoStreaming) ||
        streamEmitter == null) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('feature_or_emitter_unavailable');
      return null;
    }
    if (queryRequest.pagination != null) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('paginated_request');
      return null;
    }
    if (queryRequest.expectMultipleResults) {
      if (queryRequest.parameters?.isNotEmpty ?? false) {
        _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('multi_result_named_parameters');
        return null;
      }
      return _tryMultiResultStreamingFromDb(
        request: request,
        queryRequest: queryRequest,
        sql: sql,
        streamEmitter: streamEmitter,
        limits: limits,
        deadline: deadline,
        timeoutMs: timeoutMs,
        negotiatedExtensions: negotiatedExtensions,
        effectiveMaxRows: effectiveMaxRows,
        clientToken: clientToken,
        database: database,
      );
    }
    if (!preferDbStreaming &&
        _autoPolicy.shouldMaterializeBoundedDbStreaming(
          normalizedSql,
          effectiveMaxRows: effectiveMaxRows,
          limits: limits,
        )) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('bounded_request');
      return null;
    }
    final configResolver = _activeConfigResolver;
    final legacyRepository = _configRepository;
    final gateway = _streamingGateway;
    if ((configResolver == null && legacyRepository == null) || gateway == null) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('gateway_unavailable');
      return null;
    }
    final streamingDiagnostics = gateway is IStreamingGatewayDiagnostics
        ? gateway as IStreamingGatewayDiagnostics
        : null;
    if (!_featureFlags.enableSocketStreamingChunks &&
        autoStreamingReason == DbStreamingAutoReason.prefer &&
        streamingDiagnostics?.getStreamingDiagnostics()['direct_limiter_saturated'] == true) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('direct_limiter_saturated_prefer_fallback');
      return null;
    }
    var preparedExecution = OdbcPreparedQueryExecution(
      sql: sql,
      parameters: queryRequest.parameters,
    );
    if (queryRequest.parameters?.isNotEmpty ?? false) {
      final prepared = _streamingNamedParameterPreparer.prepare(
        sql: sql,
        parameters: queryRequest.parameters,
      );
      if (prepared.isError()) {
        _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('bound_parameters_invalid');
        return null;
      }
      preparedExecution = prepared.getOrThrow();
    }
    if (SqlValidator.validateSelectQuery(sql).isError()) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('non_select_sql');
      return null;
    }

    final config = await _resolveStreamingConfig(
      configResolver: configResolver,
      legacyRepository: legacyRepository,
    );
    final connectionString = config == null
        ? ''
        : resolveSqlStreamingConnectionString(config, databaseOverride: database);
    if (config == null || connectionString.trim().isEmpty) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('config_unavailable');
      return null;
    }
    if (!_autoPolicy.isDriverAllowed(config.driverName)) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('driver_not_allowed');
      return null;
    }

    final streamId = 'stream-${queryRequest.id}';
    final executionId = _uuid.v4();
    var totalRows = 0;
    var chunkIndex = 0;
    var overflowed = false;
    List<Map<String, dynamic>>? columnMetadata;
    final activeStreamExecution = _sqlStreamingCoordinator.markStarted(
      streamId: streamId,
      requestId: request.id?.toString(),
      executionId: executionId,
      clientToken: clientToken,
    );

    try {
      final queryTimeout = mergeOdbcTimeout(
        stageTimeout: _support.effectiveStageTimeout(
          deadline: deadline,
          stageBudget: _sqlExecuteTotalBudget,
        ),
        timeoutMs: timeoutMs,
      );
      final useColumnarWire = isOdbcStreamColumnarWireEnabled();
      final useWireOnly = resolveOdbcStreamWireOnlyEnabled(
        negotiatedExtensions: negotiatedExtensions,
      );
      final streamingParameters = preparedExecution.parameters;
      final streamingSql = preparedExecution.sql;
      Future<void> emitRows(List<Map<String, dynamic>> chunk, {Map<String, dynamic>? columnar}) async {
        if (columnMetadata == null) {
          if (chunk.isNotEmpty) {
            columnMetadata = chunk.first.keys.map((k) => <String, dynamic>{'name': k, 'type': 'string'}).toList();
          } else if (columnar != null) {
            columnMetadata = buildStreamingColumnMetadataFromWireColumnar(columnar);
          }
        }
        final effectiveRowCount = (useWireOnly || (useColumnarWire && columnar != null))
            ? (columnar?['row_count'] as int? ?? 0)
            : chunk.length;
        totalRows += effectiveRowCount;
        final currentChunkIndex = chunkIndex++;
        final skipRowMaps = useWireOnly || (useColumnarWire && columnar != null);
        final accepted = await streamEmitter.emitChunk(
          RpcStreamChunk(
            streamId: streamId,
            requestId: request.id,
            chunkIndex: currentChunkIndex,
            rows: skipRowMaps ? const <Map<String, dynamic>>[] : chunk,
            columnMetadata: currentChunkIndex == 0 ? columnMetadata : null,
            columnar: columnar,
          ),
        );
        if (!accepted) {
          overflowed = true;
          await gateway.cancelActiveStream(
            executionId: executionId,
            reason: StreamingCancelReason.backpressureOverflow,
          );
        }
      }

      Future<void> emitWireChunk(StreamingWireChunk wireChunk) =>
          emitRows(wireChunk.rows, columnar: wireChunk.columnar);

      final streamResult = await gateway.executeQueryStream(
        streamingSql.trim(),
        connectionString,
        emitRows,
        onWireChunk: useColumnarWire ? emitWireChunk : null,
        parameters: streamingParameters,
        columnarWireOnly: useWireOnly,
        fetchSize: limits.streamingChunkSize,
        chunkSizeBytes:
            (_odbcConnectionSettings?.streamingChunkSizeKb ?? ConnectionConstants.defaultStreamingChunkSizeKb) * 1024,
        executionId: executionId,
        queryTimeout: queryTimeout,
        cancellationToken: activeStreamExecution.cancellationToken,
        cancellationReasonProvider: () => activeStreamExecution.cancelReason,
      );

      if (streamResult.isError()) {
        final failure = streamResult.exceptionOrNull()! as domain.Failure;
        final isBackpressure = failure.context['reason'] == RpcStreamingConstants.backpressureOverflowReason;
        await _terminalEmitter.emitTerminalComplete(
          streamEmitter: streamEmitter,
          streamId: streamId,
          requestId: request.id,
          totalRows: totalRows,
          status: isBackpressure ? StreamTerminalStatus.aborted : StreamTerminalStatus.error,
        );
        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      }

      if (overflowed) {
        await _terminalEmitter.emitTerminalComplete(
          streamEmitter: streamEmitter,
          streamId: streamId,
          requestId: request.id,
          totalRows: totalRows,
          status: StreamTerminalStatus.aborted,
        );
        return RpcResponse.error(
          id: request.id,
          error: RpcError(
            code: RpcErrorCode.resultTooLarge,
            message: RpcErrorCode.getMessage(RpcErrorCode.resultTooLarge),
            data: RpcErrorCode.buildErrorData(
              code: RpcErrorCode.resultTooLarge,
              technicalMessage:
                  'Streaming buffer overflowed: hub not consuming fast enough; '
                  'stream cancelled to avoid data loss.',
              correlationId: request.id?.toString(),
              subreason: RpcStreamingConstants.backpressureOverflowReason,
            ),
          ),
        );
      }

      final executionStartedAtUtc = queryRequest.timestamp.toUtc();
      final executionFinishedAtUtc = DateTime.now().toUtc();
      final startedAtIso = SqlExecuteResultMapper.executionTimestampUtcIso(executionStartedAtUtc);
      final finishedAtIso = SqlExecuteResultMapper.executionTimestampUtcIso(executionFinishedAtUtc);
      await streamEmitter.emitComplete(
        RpcStreamComplete(
          streamId: streamId,
          requestId: request.id,
          totalRows: totalRows,
          affectedRows: totalRows,
          executionId: executionId,
          startedAt: startedAtIso,
          finishedAt: finishedAtIso,
        ),
      );
      final dbStreamResponse = RpcResponse.success(
        id: request.id,
        result: {
          'stream_id': streamId,
          'execution_id': executionId,
          'started_at': startedAtIso,
          'finished_at': finishedAtIso,
          'sql_handling_mode': queryRequest.sqlHandlingMode.name,
          'max_rows_handling': 'response_truncation',
          'effective_max_rows': effectiveMaxRows,
          'rows': <Map<String, dynamic>>[],
          'row_count': 0,
          'affected_rows': totalRows,
          ...?(columnMetadata != null ? {'column_metadata': columnMetadata} : null),
        },
      );
      if (autoStreaming && !_featureFlags.enableSocketStreamingChunks) {
        switch (autoStreamingReason) {
          case DbStreamingAutoReason.prefer:
            _dispatchMetrics?.recordSqlExecutePreferDbStreamingResponse();
          case DbStreamingAutoReason.largeMaxRows:
            _dispatchMetrics?.recordSqlExecuteAutoStreamingFromDbResponse();
          case DbStreamingAutoReason.allowlist:
            _dispatchMetrics?.recordSqlExecuteAutoStreamingFromDbResponse();
            _dispatchMetrics?.recordSqlExecuteAllowlistDbStreamingResponse();
          case DbStreamingAutoReason.sqlLength:
          case DbStreamingAutoReason.sqlSignal:
            _dispatchMetrics?.recordSqlExecuteAutoStreamingFromDbResponse();
          case DbStreamingAutoReason.none:
            break;
        }
      }
      _dispatchMetrics?.recordSqlExecuteStreamingFromDbResponse();
      return dbStreamResponse;
    } finally {
      _sqlStreamingCoordinator.markFinished(activeStreamExecution);
    }
  }

  Future<RpcResponse?> _tryMultiResultStreamingFromDb({
    required RpcRequest request,
    required QueryRequest queryRequest,
    required String sql,
    required IRpcStreamEmitter? streamEmitter,
    required TransportLimits limits,
    required DateTime? deadline,
    required int timeoutMs,
    required Map<String, dynamic> negotiatedExtensions,
    required int effectiveMaxRows,
    String? clientToken,
    String? database,
  }) async {
    if (!supportsStreamingChunks(negotiatedExtensions) ||
        !_featureFlags.enableSocketStreamingFromDb ||
        streamEmitter == null) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('multi_result_prerequisites_unmet');
      return null;
    }
    final gateway = _streamingGateway;
    if (gateway == null) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('multi_result_gateway_unavailable');
      return null;
    }

    final config = await _resolveStreamingConfig(
      configResolver: _activeConfigResolver,
      legacyRepository: _configRepository,
    );
    final connectionString = config == null
        ? ''
        : resolveSqlStreamingConnectionString(config, databaseOverride: database);
    if (config == null || connectionString.trim().isEmpty) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('multi_result_config_unavailable');
      return null;
    }

    final streamId = 'stream-${queryRequest.id}';
    final executionId = _uuid.v4();
    var totalRows = 0;
    var chunkIndex = 0;
    final activeStreamExecution = _sqlStreamingCoordinator.markStarted(
      streamId: streamId,
      requestId: request.id?.toString(),
      executionId: executionId,
      clientToken: clientToken,
    );

    try {
      final queryTimeout = mergeOdbcTimeout(
        stageTimeout: _support.effectiveStageTimeout(
          deadline: deadline,
          stageBudget: _sqlExecuteTotalBudget,
        ),
        timeoutMs: timeoutMs,
      );
      final streamResult = await gateway.executeMultiResultQueryStream(
        sql.trim(),
        connectionString,
        (wireChunk) async {
          if (wireChunk.rowCountOnly != null) {
            return;
          }
          totalRows += wireChunk.rows.length;
          await streamEmitter.emitChunk(
            RpcStreamChunk(
              streamId: streamId,
              requestId: request.id,
              chunkIndex: chunkIndex++,
              rows: wireChunk.rows,
              columnMetadata: wireChunk.resultSetIndex == 0 && wireChunk.rows.isNotEmpty
                  ? wireChunk.rows.first.keys
                        .map((name) => <String, dynamic>{'name': name, 'result_set_index': wireChunk.resultSetIndex})
                        .toList()
                  : null,
            ),
          );
        },
        executionId: executionId,
        queryTimeout: queryTimeout,
        cancellationToken: activeStreamExecution.cancellationToken,
        cancellationReasonProvider: () => activeStreamExecution.cancelReason,
      );

      if (streamResult.isError()) {
        final failure = streamResult.exceptionOrNull()! as domain.Failure;
        await _terminalEmitter.emitTerminalComplete(
          streamEmitter: streamEmitter,
          streamId: streamId,
          requestId: request.id,
          totalRows: totalRows,
          status: StreamTerminalStatus.error,
        );
        return RpcResponse.error(
          id: request.id,
          error: FailureToRpcErrorMapper.map(
            failure,
            instance: request.id?.toString(),
            useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
          ),
        );
      }

      final startedAtIso = SqlExecuteResultMapper.executionTimestampUtcIso(queryRequest.timestamp.toUtc());
      final finishedAtIso = SqlExecuteResultMapper.executionTimestampUtcIso(DateTime.now().toUtc());
      await streamEmitter.emitComplete(
        RpcStreamComplete(
          streamId: streamId,
          requestId: request.id,
          totalRows: totalRows,
          affectedRows: totalRows,
          executionId: executionId,
          startedAt: startedAtIso,
          finishedAt: finishedAtIso,
        ),
      );
      _dispatchMetrics?.recordSqlExecuteStreamingFromDbResponse();
      return RpcResponse.success(
        id: request.id,
        result: {
          'stream_id': streamId,
          'execution_id': executionId,
          'started_at': startedAtIso,
          'finished_at': finishedAtIso,
          'sql_handling_mode': queryRequest.sqlHandlingMode.name,
          'max_rows_handling': 'response_truncation',
          'effective_max_rows': effectiveMaxRows,
          'rows': <Map<String, dynamic>>[],
          'row_count': 0,
          'affected_rows': totalRows,
          'multi_result': true,
        },
      );
    } finally {
      _sqlStreamingCoordinator.markFinished(activeStreamExecution);
    }
  }

  Future<Config?> _resolveStreamingConfig({
    required ActiveConfigResolver? configResolver,
    required IAgentConfigRepository? legacyRepository,
  }) async {
    if (configResolver != null) {
      return (await configResolver.resolveActiveForDatabaseAccess()).getOrNull();
    }
    if (legacyRepository != null) {
      return (await legacyRepository.getCurrentConfig()).getOrNull();
    }
    return null;
  }
}
