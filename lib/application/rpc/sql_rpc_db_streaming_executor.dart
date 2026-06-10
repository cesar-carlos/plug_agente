import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/rpc/sql_db_streaming_auto_policy.dart';
import 'package:plug_agente/application/rpc/sql_execute_result_mapper.dart';
import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/application/rpc/sql_rpc_negotiated_capabilities.dart';
import 'package:plug_agente/application/rpc/sql_rpc_stream_terminal_emitter.dart';
import 'package:plug_agente/application/rpc/sql_streaming_coordinator.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_streaming_constants.dart';
import 'package:plug_agente/core/utils/batch_odbc_timeout.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
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
       _odbcConnectionSettings = odbcConnectionSettings;

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
  }) async {
    final normalizedSql = _autoPolicy.normalizeSqlForDbStreaming(sql);
    final autoStreamingReason = _autoPolicy.resolveAutoReason(
      featureFlags: _featureFlags,
      queryRequest: queryRequest,
      sql: sql,
      negotiatedExtensions: negotiatedExtensions,
      preferDbStreaming: preferDbStreaming,
    );
    final autoStreaming = autoStreamingReason != DbStreamingAutoReason.none;
    if (!supportsStreamingChunks(negotiatedExtensions)) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('streaming_chunks_not_negotiated');
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
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('multi_result_request');
      return null;
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
    if (queryRequest.parameters?.isNotEmpty ?? false) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('bound_parameters');
      return null;
    }
    if (SqlValidator.validateSelectQuery(sql).isError()) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('non_select_sql');
      return null;
    }

    final configResult = configResolver != null
        ? await configResolver.resolveActiveOrFallback(
            metadataOnly: true,
          )
        : await legacyRepository!.getCurrentConfigMetadata();
    final config = configResult.getOrNull();
    if (config == null || config.resolveConnectionString().trim().isEmpty) {
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
      final streamResult = await gateway.executeQueryStream(
        sql.trim(),
        config.resolveConnectionString(),
        (chunk) async {
          if (columnMetadata == null && chunk.isNotEmpty) {
            columnMetadata = chunk.first.keys.map((k) => <String, dynamic>{'name': k, 'type': 'string'}).toList();
          }
          totalRows += chunk.length;
          final accepted = await streamEmitter.emitChunk(
            RpcStreamChunk(
              streamId: streamId,
              requestId: request.id,
              chunkIndex: chunkIndex++,
              rows: chunk,
              columnMetadata: columnMetadata,
            ),
          );
          if (!accepted) {
            overflowed = true;
            await gateway.cancelActiveStream(
              executionId: executionId,
              reason: StreamingCancelReason.backpressureOverflow,
            );
          }
        },
        fetchSize: limits.streamingChunkSize,
        chunkSizeBytes:
            (_odbcConnectionSettings?.streamingChunkSizeKb ?? ConnectionConstants.defaultStreamingChunkSizeKb) *
            1024,
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
}
