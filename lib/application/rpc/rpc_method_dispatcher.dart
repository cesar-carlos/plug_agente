import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/idempotency_fingerprint.dart';
import 'package:plug_agente/application/rpc/sql_execute_params_reader.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/execute_sql_batch.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/utils/batch_odbc_timeout.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/core/utils/split_sql_statements.dart' show sqlStatementsForClientTokenAuthorization;
import 'package:plug_agente/core/utils/sql_row_truncation.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:plug_agente/domain/utils/json_primitive_coercion.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_native_metrics_service.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

/// RPC method dispatcher for routing JSON-RPC requests to handlers.
class RpcMethodDispatcher {
  RpcMethodDispatcher({
    required IDatabaseGateway databaseGateway,
    required HealthService healthService,
    required QueryNormalizerService normalizerService,
    required Uuid uuid,
    required AuthorizeSqlOperation authorizeSqlOperation,
    required GetClientTokenPolicy getClientTokenPolicy,
    required ClientTokenGetPolicyRateLimiter getPolicyRateLimiter,
    required FeatureFlags featureFlags,
    IAgentConfigRepository? configRepository,
    IIdempotencyStore? idempotencyStore,
    IAuthorizationMetricsCollector? authMetrics,
    IDeprecationMetricsCollector? deprecationMetrics,
    IRpcDispatchMetricsCollector? dispatchMetrics,
    void Function()? onIdempotencyFingerprintMismatch,
    IStreamingDatabaseGateway? streamingGateway,
    OdbcNativeMetricsService? odbcNativeMetricsService,
    TransportLimits defaultLimits = const TransportLimits(),
    Duration sqlExecuteTotalBudget = _defaultSqlExecuteTotalBudget,
    Duration sqlBatchTotalBudget = _defaultSqlBatchTotalBudget,
    Duration authorizationStageBudget = _defaultAuthorizationStageBudget,
    Duration queryStageBudget = _defaultQueryStageBudget,
    Duration batchExecutionStageBudget = _defaultBatchExecutionStageBudget,
  }) : _databaseGateway = databaseGateway,
       _healthService = healthService,
       _normalizerService = normalizerService,
       _uuid = uuid,
       _authorizeSqlOperation = authorizeSqlOperation,
       _getClientTokenPolicy = getClientTokenPolicy,
       _getPolicyRateLimiter = getPolicyRateLimiter,
       _featureFlags = featureFlags,
       _configRepository = configRepository,
       _idempotencyStore = idempotencyStore,
       _authMetrics = authMetrics,
       _deprecationMetrics = deprecationMetrics,
       _dispatchMetrics = dispatchMetrics,
       _onIdempotencyFingerprintMismatch = onIdempotencyFingerprintMismatch,
       _streamingGateway = streamingGateway,
       _odbcNativeMetricsService = odbcNativeMetricsService,
       _defaultLimits = defaultLimits,
       _sqlExecuteTotalBudgetDuration = sqlExecuteTotalBudget,
       _sqlBatchTotalBudgetDuration = sqlBatchTotalBudget,
       _authorizationStageBudgetDuration = authorizationStageBudget,
       _queryStageBudgetDuration = queryStageBudget,
       _batchExecutionStageBudgetDuration = batchExecutionStageBudget,
       _executeSqlBatch = ExecuteSqlBatch(
         databaseGateway,
         normalizerService,
         uuid,
       );

  final IDatabaseGateway _databaseGateway;
  final HealthService _healthService;
  final QueryNormalizerService _normalizerService;
  final Uuid _uuid;
  final AuthorizeSqlOperation _authorizeSqlOperation;
  final GetClientTokenPolicy _getClientTokenPolicy;
  final ClientTokenGetPolicyRateLimiter _getPolicyRateLimiter;
  final FeatureFlags _featureFlags;
  final IAgentConfigRepository? _configRepository;
  final IIdempotencyStore? _idempotencyStore;
  final IAuthorizationMetricsCollector? _authMetrics;
  final IDeprecationMetricsCollector? _deprecationMetrics;
  final IRpcDispatchMetricsCollector? _dispatchMetrics;
  final void Function()? _onIdempotencyFingerprintMismatch;
  final IStreamingDatabaseGateway? _streamingGateway;
  final OdbcNativeMetricsService? _odbcNativeMetricsService;
  final TransportLimits _defaultLimits;
  final Duration _sqlExecuteTotalBudgetDuration;
  final Duration _sqlBatchTotalBudgetDuration;
  final Duration _authorizationStageBudgetDuration;
  final Duration _queryStageBudgetDuration;
  final Duration _batchExecutionStageBudgetDuration;

  static const _idempotencyTtl = Duration(minutes: 5);
  static final RegExp _authorizationSqlWhitespaceCollapse = RegExp(r'\s+');
  static const _defaultSqlExecuteTotalBudget = Duration(seconds: 35);
  static const _defaultSqlBatchTotalBudget = Duration(seconds: 45);
  static const _defaultAuthorizationStageBudget = Duration(seconds: 3);
  static const _defaultQueryStageBudget = Duration(seconds: 30);
  static const _defaultBatchExecutionStageBudget = Duration(seconds: 35);
  static const _agentProfileAuthorizationSql = 'SELECT * FROM agent_profile';
  final ExecuteSqlBatch _executeSqlBatch;
  _ActiveStreamExecution? _activeStreamExecution;

  /// Dispatches an RPC request to the appropriate handler.
  Future<RpcResponse> dispatch(
    RpcRequest request,
    String agentId, {
    String? clientToken,
    IRpcStreamEmitter? streamEmitter,
    TransportLimits? limits,
    Map<String, dynamic> negotiatedExtensions = const {},
  }) async {
    final effectiveLimits = limits ?? _defaultLimits;
    return switch (request.method) {
      'sql.execute' => await _handleSqlExecute(
        request,
        agentId,
        clientToken,
        streamEmitter: streamEmitter,
        limits: effectiveLimits,
        negotiatedExtensions: negotiatedExtensions,
      ),
      'sql.executeBatch' => await _handleSqlExecuteBatch(
        request,
        agentId,
        clientToken,
        limits: effectiveLimits,
        negotiatedExtensions: negotiatedExtensions,
      ),
      'sql.cancel' => await _handleSqlCancel(request),
      'agent.getProfile' => await _handleAgentGetProfile(
        request,
        agentId,
        clientToken,
      ),
      'agent.getHealth' => await _handleAgentGetHealth(
        request,
        clientToken,
      ),
      'client_token.getPolicy' => await _handleClientTokenGetPolicy(
        request,
        agentId,
        clientToken,
      ),
      _ => _methodNotFound(request),
    };
  }

  /// Cancels any active ODBC stream when the socket disconnects.
  ///
  /// Called by the transport client on disconnect to release ODBC resources.
  Future<void> cancelActiveStreamOnDisconnect() async {
    final gateway = _streamingGateway;
    if (gateway == null || !gateway.hasActiveStream) return;
    await gateway.cancelActiveStream(
      reason: StreamingCancelReason.socketDisconnect,
    );
    _activeStreamExecution = null;
  }

  /// Handles sql.execute method (single command).
  Future<RpcResponse> _handleSqlExecute(
    RpcRequest request,
    String agentId,
    String? clientToken, {
    required TransportLimits limits,
    required Map<String, dynamic> negotiatedExtensions,
    IRpcStreamEmitter? streamEmitter,
  }) async {
    // Validate params
    if (request.params is! Map<String, dynamic>) {
      return _invalidParams(request, 'params must be an object');
    }

    final params = request.params as Map<String, dynamic>;
    final paramReader = SqlExecuteParamsReader(params);
    final sql = paramReader.sql;
    final maxRows = _resolveMaxRows(params, limits.maxRows);
    final deadline = _featureFlags.enableSocketTimeoutByStage
        ? DateTime.now().add(_sqlExecuteTotalBudgetDuration)
        : null;

    if (sql == null || sql.isEmpty) {
      return _invalidParams(request, 'sql is required');
    }
    final options = paramReader.options;
    if (options?['preserve_sql'] == true) {
      _deprecationMetrics?.recordPreserveSqlUsage(
        requestId: request.id?.toString(),
        method: request.method,
      );
    }
    final sqlHandlingModeResolution = _resolveSqlHandlingMode(params);
    if (sqlHandlingModeResolution.hasError) {
      return _invalidParams(
        request,
        sqlHandlingModeResolution.errorMessage!,
      );
    }
    final sqlHandlingMode = sqlHandlingModeResolution.sqlHandlingMode!;
    final paginationResolution = sqlHandlingMode == SqlHandlingMode.preserve
        ? const _ResolvedPagination()
        : _resolvePagination(
            params,
            sql,
            maxRows,
            negotiatedExtensions,
          );
    if (paginationResolution.hasError) {
      return _invalidParams(request, paginationResolution.errorMessage!);
    }
    final pagination = paginationResolution.pagination;
    final multiResultRequested = _resolveMultiResult(params);
    final requestParameters = paramReader.boundParams;
    final database = paramReader.database;

    if (multiResultRequested && requestParameters != null && requestParameters.isNotEmpty) {
      return _invalidParams(
        request,
        'multi_result is not supported with named parameters',
      );
    }
    if (multiResultRequested && pagination != null) {
      return _invalidParams(
        request,
        'multi_result cannot be combined with pagination',
      );
    }

    final idempotencyKey = paramReader.idempotencyKey;
    final idempotencyFingerprint = await resolveIdempotencyFingerprint(
      request.method,
      params,
    );
    final idempotentEarly = _consumeIdempotentCacheIfAny(
      request,
      idempotencyKey,
      idempotencyFingerprint,
    );
    if (idempotentEarly != null) {
      return idempotentEarly;
    }

    if (_featureFlags.enableClientTokenAuthorization && (clientToken == null || clientToken.isEmpty)) {
      _authMetrics?.recordDenied(
        requestId: request.id?.toString(),
        method: request.method,
        reason: 'missing_client_token',
      );
      final rpcError = FailureToRpcErrorMapper.map(
        _buildMissingClientTokenFailure(),
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    if (_featureFlags.enableClientTokenAuthorization && clientToken != null && clientToken.isNotEmpty) {
      final authDenied = await _authorizeSqlExecuteWithClientToken(
        request: request,
        sql: sql,
        multiResultRequested: multiResultRequested,
        clientToken: clientToken,
        deadline: deadline,
      );
      if (authDenied != null) {
        return authDenied;
      }
    }

    // Validate SQL (allows SELECT, WITH, UPDATE, INSERT, MERGE, DELETE)
    final validation = SqlValidator.validateSqlForExecution(
      sql,
      allowMultipleStatements: multiResultRequested,
    );
    if (validation.isError()) {
      final failure = validation.exceptionOrNull()! as domain.Failure;
      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final queryRequest = QueryRequest(
      id: _uuid.v4(),
      agentId: agentId,
      query: sql,
      parameters: requestParameters,
      timestamp: DateTime.now(),
      pagination: pagination,
      expectMultipleResults: multiResultRequested,
      sqlHandlingMode: sqlHandlingMode,
    );

    final streamingFromDbResponse = await _tryStreamingFromDb(
      request,
      queryRequest,
      sql,
      request.isNotification ? null : streamEmitter,
      limits: limits,
    );
    if (streamingFromDbResponse != null) {
      return streamingFromDbResponse;
    }

    final result = await _executeQueryWithBudget(
      queryRequest,
      database: database,
      requestId: request.id?.toString(),
      deadline: deadline,
    );

    return result.fold<Future<RpcResponse>>(
      (QueryResponse queryResponse) async {
        // Normalize
        var normalized = _normalizerService.normalize(queryResponse);

        var multiResultSetsTruncated = false;
        if (normalized.resultSets.isNotEmpty) {
          final beforeMulti = normalized;
          normalized = _applyMaxRowsToMultiResultSets(normalized, maxRows);
          multiResultSetsTruncated = _multiResultSetsWereTruncated(
            beforeMulti,
            normalized,
          );
        }

        final limitedRows = normalized.resultSets.isNotEmpty
            ? normalized.data
            : truncateSqlResultRows(normalized.data, maxRows);
        final wasTruncated =
            multiResultSetsTruncated ||
            (!normalized.resultSets.isNotEmpty && limitedRows.length != normalized.data.length);
        final useStreaming =
            _featureFlags.enableSocketStreamingChunks &&
            streamEmitter != null &&
            !request.isNotification &&
            pagination == null &&
            !normalized.hasMultiResult &&
            limitedRows.length > limits.streamingRowThreshold;

        if (useStreaming) {
          final streamId = 'stream-${queryRequest.id}';
          final rows = limitedRows;
          final totalChunks = (rows.length / limits.streamingChunkSize).ceil();
          var overflowed = false;

          for (var i = 0; i < rows.length && !overflowed; i += limits.streamingChunkSize) {
            final chunkEnd = i + limits.streamingChunkSize > rows.length ? rows.length : i + limits.streamingChunkSize;
            final chunkRows = rows.sublist(i, chunkEnd);
            if (!await streamEmitter.emitChunk(
              RpcStreamChunk(
                streamId: streamId,
                requestId: request.id,
                chunkIndex: i ~/ limits.streamingChunkSize,
                rows: chunkRows,
                totalChunks: totalChunks,
                columnMetadata: normalized.columnMetadata,
              ),
            )) {
              overflowed = true;
              break;
            }
          }

          if (!overflowed) {
            _dispatchMetrics?.recordSqlExecuteStreamingChunksResponse();
          }

          if (overflowed) {
            await _emitTerminalComplete(
              streamEmitter: streamEmitter,
              streamId: streamId,
              requestId: request.id,
              totalRows: rows.length,
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
                  subreason: 'backpressure_overflow',
                ),
              ),
            );
          }

          await streamEmitter.emitComplete(
            RpcStreamComplete(
              streamId: streamId,
              requestId: request.id,
              totalRows: rows.length,
              affectedRows: normalized.affectedRows,
              executionId: normalized.id,
              startedAt: queryRequest.timestamp.toIso8601String(),
              finishedAt: normalized.timestamp.toIso8601String(),
            ),
          );

          final resultData = {
            'stream_id': streamId,
            'execution_id': normalized.id,
            'started_at': queryRequest.timestamp.toIso8601String(),
            'finished_at': normalized.timestamp.toIso8601String(),
            'sql_handling_mode': queryRequest.sqlHandlingMode.name,
            'max_rows_handling': 'response_truncation',
            'effective_max_rows': maxRows,
            'rows': <Map<String, dynamic>>[],
            'row_count': 0,
            'affected_rows': normalized.affectedRows,
            'returned_rows': rows.length,
            if (wasTruncated) 'truncated': true,
            if (normalized.columnMetadata != null) 'column_metadata': normalized.columnMetadata,
            if (normalized.pagination != null) 'pagination': _buildPaginationResult(normalized.pagination!),
          };

          return RpcResponse.success(id: request.id, result: resultData);
        }

        final resultData = _buildExecuteResultData(
          normalized,
          startedAt: queryRequest.timestamp,
          finishedAt: normalized.timestamp,
          limitedRows: limitedRows,
          wasTruncated: wasTruncated,
          sqlHandlingMode: queryRequest.sqlHandlingMode,
          effectiveMaxRows: maxRows,
          forceMultiResultEnvelope: multiResultRequested,
        );

        final rpcResponse = RpcResponse.success(
          id: request.id,
          result: resultData,
        );
        _dispatchMetrics?.recordSqlExecuteMaterializedResponse();
        _storeIdempotentSuccessIfApplicable(
          request: request,
          idempotencyKey: idempotencyKey,
          idempotencyFingerprint: idempotencyFingerprint,
          response: rpcResponse,
        );
        return rpcResponse;
      },
      (Exception failure) async {
        final rpcError = FailureToRpcErrorMapper.map(
          failure as domain.Failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      },
    );
  }

  /// Tries to stream directly from DB when enabled. Returns null to fall back.
  Future<RpcResponse?> _tryStreamingFromDb(
    RpcRequest request,
    QueryRequest queryRequest,
    String sql,
    IRpcStreamEmitter? streamEmitter, {
    required TransportLimits limits,
  }) async {
    if (!_featureFlags.enableSocketStreamingFromDb ||
        !_featureFlags.enableSocketStreamingChunks ||
        streamEmitter == null) {
      return null;
    }
    if (queryRequest.pagination != null) {
      return null;
    }
    if (queryRequest.expectMultipleResults) {
      return null;
    }
    final configRepo = _configRepository;
    final gateway = _streamingGateway;
    if (configRepo == null || gateway == null) {
      return null;
    }
    if (queryRequest.parameters?.isNotEmpty ?? false) {
      return null;
    }
    if (SqlValidator.validateSelectQuery(sql).isError()) {
      return null;
    }

    final configResult = await configRepo.getCurrentConfig();
    final config = configResult.getOrNull();
    if (config == null || config.resolveConnectionString().trim().isEmpty) {
      return null;
    }

    final streamId = 'stream-${queryRequest.id}';
    final executionId = _uuid.v4();
    var totalRows = 0;
    var chunkIndex = 0;
    List<Map<String, dynamic>>? columnMetadata;
    _activeStreamExecution = _ActiveStreamExecution(
      streamId: streamId,
      requestId: request.id?.toString(),
      executionId: executionId,
    );

    try {
      final streamResult = await gateway.executeQueryStream(
        sql.trim(),
        config.resolveConnectionString(),
        (chunk) async {
          if (columnMetadata == null && chunk.isNotEmpty) {
            columnMetadata = chunk.first.keys.map((k) => <String, dynamic>{'name': k, 'type': 'string'}).toList();
          }
          totalRows += chunk.length;
          if (!await streamEmitter.emitChunk(
            RpcStreamChunk(
              streamId: streamId,
              requestId: request.id,
              chunkIndex: chunkIndex++,
              rows: chunk,
              columnMetadata: columnMetadata,
            ),
          )) {
            await gateway.cancelActiveStream(
              executionId: executionId,
              reason: StreamingCancelReason.backpressureOverflow,
            );
          }
        },
        fetchSize: limits.streamingChunkSize,
        executionId: executionId,
        queryTimeout: _sqlExecuteTotalBudgetDuration,
      );

      if (streamResult.isError()) {
        final failure = streamResult.exceptionOrNull()! as domain.Failure;
        final isBackpressure = failure.context['reason'] == 'backpressure_overflow';
        await _emitTerminalComplete(
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

      await streamEmitter.emitComplete(
        RpcStreamComplete(
          streamId: streamId,
          requestId: request.id,
          totalRows: totalRows,
          affectedRows: totalRows,
          executionId: executionId,
          startedAt: queryRequest.timestamp.toIso8601String(),
          finishedAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      final dbStreamResponse = RpcResponse.success(
        id: request.id,
        result: {
          'stream_id': streamId,
          'execution_id': executionId,
          'started_at': queryRequest.timestamp.toIso8601String(),
          'finished_at': DateTime.now().toUtc().toIso8601String(),
          'sql_handling_mode': queryRequest.sqlHandlingMode.name,
          'max_rows_handling': 'response_truncation',
          'effective_max_rows': limits.maxRows,
          'rows': <Map<String, dynamic>>[],
          'row_count': 0,
          'affected_rows': totalRows,
          ...?(columnMetadata != null ? {'column_metadata': columnMetadata} : null),
        },
      );
      _dispatchMetrics?.recordSqlExecuteStreamingFromDbResponse();
      return dbStreamResponse;
    } finally {
      _activeStreamExecution = null;
    }
  }

  /// Handles sql.executeBatch method (multiple commands).
  Future<RpcResponse> _handleSqlExecuteBatch(
    RpcRequest request,
    String agentId,
    String? clientToken, {
    required TransportLimits limits,
    required Map<String, dynamic> negotiatedExtensions,
  }) async {
    // Validate params
    if (request.params is! Map<String, dynamic>) {
      return _invalidParams(request, 'params must be an object');
    }

    final params = request.params as Map<String, dynamic>;
    final commandsJson = params['commands'] as List<dynamic>?;
    final deadline = _featureFlags.enableSocketTimeoutByStage ? DateTime.now().add(_sqlBatchTotalBudgetDuration) : null;
    if (!_supportsPageOffsetPagination(negotiatedExtensions)) {
      final options = params['options'] as Map<String, dynamic>?;
      if (options?['page'] != null || options?['page_size'] != null) {
        return _invalidParams(
          request,
          'Negotiated protocol does not allow page-offset pagination',
        );
      }
    }

    if (commandsJson == null || commandsJson.isEmpty) {
      return _invalidParams(
        request,
        'commands is required and must not be empty',
      );
    }

    if (commandsJson.length > limits.maxBatchSize) {
      return _invalidParams(
        request,
        'commands exceeds negotiated limit: '
        '${commandsJson.length} > ${limits.maxBatchSize}',
      );
    }

    final idempotencyKey = params['idempotency_key'] as String?;
    final idempotencyFingerprint = await resolveIdempotencyFingerprint(
      request.method,
      params,
    );
    final idempotentEarly = _consumeIdempotentCacheIfAny(
      request,
      idempotencyKey,
      idempotencyFingerprint,
    );
    if (idempotentEarly != null) {
      return idempotentEarly;
    }

    // Parse commands and build execution plan
    final commandPlans = <_BatchCommandExecutionPlan>[];
    for (var i = 0; i < commandsJson.length; i++) {
      final commandJson = commandsJson[i];
      if (commandJson is! Map<String, dynamic>) {
        return _invalidParams(request, 'commands[$i] must be an object');
      }

      final executionOrderRaw = commandJson['execution_order'];
      final executionOrder = executionOrderRaw != null ? jsonNonNegativeInt(executionOrderRaw) : null;
      if (executionOrderRaw != null && executionOrder == null) {
        return _invalidParams(
          request,
          'commands[$i].execution_order must be an integer >= 0',
        );
      }

      commandPlans.add(
        _BatchCommandExecutionPlan(
          command: SqlCommand.fromJson(commandJson),
          requestIndex: i,
          executionOrder: executionOrder,
        ),
      );
    }

    commandPlans.sort((left, right) {
      final leftHasExplicitOrder = left.executionOrder != null;
      final rightHasExplicitOrder = right.executionOrder != null;

      if (leftHasExplicitOrder && rightHasExplicitOrder) {
        final orderCompare = left.executionOrder!.compareTo(
          right.executionOrder!,
        );
        if (orderCompare != 0) {
          return orderCompare;
        }
        return left.requestIndex.compareTo(right.requestIndex);
      }

      if (leftHasExplicitOrder && !rightHasExplicitOrder) {
        return -1;
      }
      if (!leftHasExplicitOrder && rightHasExplicitOrder) {
        return 1;
      }
      return left.requestIndex.compareTo(right.requestIndex);
    });

    final commands = commandPlans.map((plan) => plan.command).toList(growable: false);

    if (_featureFlags.enableClientTokenAuthorization && (clientToken == null || clientToken.isEmpty)) {
      _authMetrics?.recordDenied(
        requestId: request.id?.toString(),
        method: request.method,
        reason: 'missing_client_token',
      );
      final rpcError = FailureToRpcErrorMapper.map(
        _buildMissingClientTokenFailure(),
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    if (_featureFlags.enableClientTokenAuthorization && clientToken != null && clientToken.isNotEmpty) {
      final authorizedSqlFingerprints = <String>{};
      for (final cmd in commands) {
        final authFingerprint = _authorizationFingerprint(cmd.sql);
        if (authorizedSqlFingerprints.contains(authFingerprint)) {
          continue;
        }

        final authStopwatch = Stopwatch()..start();
        final authResult = await _authorizeWithBudget(
          token: clientToken,
          sql: cmd.sql,
          requestId: request.id?.toString(),
          method: request.method,
          deadline: deadline,
        );
        authStopwatch.stop();
        if (authResult.isError()) {
          final failure = authResult.exceptionOrNull()! as domain.Failure;
          final ctx = failure.context;
          _authMetrics?.recordDenied(
            requestId: request.id?.toString(),
            method: request.method,
            latencyMs: authStopwatch.elapsedMilliseconds,
            clientId: ctx['client_id'] as String?,
            operation: ctx['operation'] as String?,
            resource: ctx['resource'] as String?,
            reason: ctx['reason'] as String?,
          );
          final rpcError = FailureToRpcErrorMapper.map(
            failure,
            instance: request.id?.toString(),
            useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
          );
          return RpcResponse.error(id: request.id, error: rpcError);
        }
        _authMetrics?.recordAuthorized(
          requestId: request.id?.toString(),
          method: request.method,
          latencyMs: authStopwatch.elapsedMilliseconds,
        );
        authorizedSqlFingerprints.add(authFingerprint);
      }
    }

    // Parse options
    final optionsJson = params['options'] as Map<String, dynamic>?;
    final options = optionsJson != null ? SqlExecutionOptions.fromJson(optionsJson) : const SqlExecutionOptions();
    final effectiveOptions = SqlExecutionOptions(
      timeoutMs: options.timeoutMs,
      maxRows: options.maxRows < limits.maxRows ? options.maxRows : limits.maxRows,
      transaction: options.transaction,
    );

    // Execute batch
    final database = params['database'] as String?;
    final batchStartedAt = DateTime.now().toUtc();
    final result = await _executeSqlBatchWithBudget(
      agentId,
      commands,
      database: database,
      options: effectiveOptions,
      requestId: request.id?.toString(),
      deadline: deadline,
    );

    return result.fold<RpcResponse>(
      (List<SqlCommandResult> commandResults) {
        final batchFinishedAt = DateTime.now().toUtc();
        final items =
            commandResults
                .map((result) {
                  if (result.index < 0 || result.index >= commandPlans.length) {
                    return result;
                  }
                  final requestIndex = commandPlans[result.index].requestIndex;
                  return SqlCommandResult(
                    index: requestIndex,
                    ok: result.ok,
                    rows: result.rows,
                    rowCount: result.rowCount,
                    affectedRows: result.affectedRows,
                    error: result.error,
                    columnMetadata: result.columnMetadata,
                  );
                })
                .toList(growable: false)
              ..sort((left, right) => left.index.compareTo(right.index));

        final resultData = {
          'execution_id': _uuid.v4(),
          'started_at': batchStartedAt.toIso8601String(),
          'finished_at': batchFinishedAt.toIso8601String(),
          'items': items.map((r) => r.toJson()).toList(growable: false),
          'total_commands': commands.length,
          'successful_commands': items.where((r) => r.ok).length,
          'failed_commands': items.where((r) => !r.ok).length,
        };

        final response = RpcResponse.success(
          id: request.id,
          result: resultData,
        );
        _storeIdempotentSuccessIfApplicable(
          request: request,
          idempotencyKey: idempotencyKey,
          idempotencyFingerprint: idempotencyFingerprint,
          response: response,
        );
        return response;
      },
      (Exception failure) {
        final rpcError = FailureToRpcErrorMapper.map(
          failure as domain.Failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      },
    );
  }

  /// When [multiResultRequested] and the script contains several statements,
  /// authorizes each fragment separately (aligned with `sql.executeBatch`).
  ///
  /// Uses [sqlStatementsForClientTokenAuthorization]: one split pass for
  /// `multi_result` instead of a separate multi-statement probe plus split.
  Future<RpcResponse?> _authorizeSqlExecuteWithClientToken({
    required RpcRequest request,
    required String sql,
    required bool multiResultRequested,
    required String clientToken,
    required DateTime? deadline,
  }) async {
    final statements = !multiResultRequested ? <String>[sql] : sqlStatementsForClientTokenAuthorization(sql);

    final authorizedFingerprints = <String>{};
    for (final raw in statements) {
      final stmt = raw.trim();
      if (stmt.isEmpty) {
        continue;
      }
      final fingerprint = _authorizationFingerprint(stmt);
      if (authorizedFingerprints.contains(fingerprint)) {
        continue;
      }
      authorizedFingerprints.add(fingerprint);

      final authStopwatch = Stopwatch()..start();
      final authResult = await _authorizeWithBudget(
        token: clientToken,
        sql: stmt,
        requestId: request.id?.toString(),
        method: request.method,
        deadline: deadline,
      );
      authStopwatch.stop();
      if (authResult.isError()) {
        final failure = authResult.exceptionOrNull()! as domain.Failure;
        final ctx = failure.context;
        _authMetrics?.recordDenied(
          requestId: request.id?.toString(),
          method: request.method,
          latencyMs: authStopwatch.elapsedMilliseconds,
          clientId: ctx['client_id'] as String?,
          operation: ctx['operation'] as String?,
          resource: ctx['resource'] as String?,
          reason: ctx['reason'] as String?,
        );
        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      }
      _authMetrics?.recordAuthorized(
        requestId: request.id?.toString(),
        method: request.method,
        latencyMs: authStopwatch.elapsedMilliseconds,
      );
    }
    return null;
  }

  Future<Result<void>> _authorizeWithBudget({
    required String token,
    required String sql,
    required String? requestId,
    required String method,
    required DateTime? deadline,
  }) async {
    final timeout = _effectiveStageTimeout(
      deadline: deadline,
      stageBudget: _authorizationStageBudgetDuration,
    );
    if (timeout != null && timeout <= Duration.zero) {
      final context = <String, dynamic>{
        'authorization': true,
        'reason': 'authorization_budget_exhausted',
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'authorization',
        'method': method,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Authorization budget exhausted before validation',
          context: context,
        ),
      );
    }

    try {
      if (timeout == null) {
        return _authorizeSqlOperation(
          token: token,
          sql: sql,
          requestId: requestId,
          method: method,
        );
      }
      return await _authorizeSqlOperation(
        token: token,
        sql: sql,
        requestId: requestId,
        method: method,
      ).timeout(timeout);
    } on TimeoutException catch (error) {
      final context = <String, dynamic>{
        'authorization': true,
        'reason': 'authorization_timeout',
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'authorization',
        'method': method,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Authorization stage timeout',
          cause: error,
          context: context,
        ),
      );
    }
  }

  Future<Result<QueryResponse>> _executeQueryWithBudget(
    QueryRequest queryRequest, {
    required String? database,
    required String? requestId,
    required DateTime? deadline,
  }) async {
    final timeout = _effectiveStageTimeout(
      deadline: deadline,
      stageBudget: _queryStageBudgetDuration,
    );
    if (timeout != null && timeout <= Duration.zero) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'query',
        'reason': 'query_budget_exhausted',
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'SQL execution budget exhausted before database call',
          context: context,
        ),
      );
    }

    try {
      if (timeout == null) {
        if (database == null || database.isEmpty) {
          return await _databaseGateway.executeQuery(queryRequest);
        }
        return await _databaseGateway.executeQuery(
          queryRequest,
          database: database,
        );
      }
      return await _databaseGateway.executeQuery(
        queryRequest,
        timeout: timeout,
        database: database,
      );
    } on TimeoutException catch (error) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'query',
        'reason': 'query_timeout',
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'SQL execution timeout',
          cause: error,
          context: context,
        ),
      );
    }
  }

  Future<Result<List<SqlCommandResult>>> _executeSqlBatchWithBudget(
    String agentId,
    List<SqlCommand> commands, {
    required String? database,
    required SqlExecutionOptions options,
    required String? requestId,
    required DateTime? deadline,
  }) async {
    final stageTimeout = _effectiveStageTimeout(
      deadline: deadline,
      stageBudget: _batchExecutionStageBudgetDuration,
    );
    final timeout = mergeBatchOdbcTimeout(
      stageTimeout: stageTimeout,
      timeoutMs: options.timeoutMs,
    );
    if (timeout != null && timeout <= Duration.zero) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'batch',
        'reason': 'batch_budget_exhausted',
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Batch execution budget exhausted before database call',
          context: context,
        ),
      );
    }

    try {
      return await _executeSqlBatch(
        agentId,
        commands,
        database: database,
        options: options,
        timeout: timeout,
      );
    } on TimeoutException catch (error) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'batch',
        'reason': 'query_timeout',
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Batch SQL execution timeout',
          cause: error,
          context: context,
        ),
      );
    }
  }

  Duration? _effectiveStageTimeout({
    required DateTime? deadline,
    required Duration stageBudget,
  }) {
    if (deadline == null) {
      return null;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return Duration.zero;
    }
    return remaining < stageBudget ? remaining : stageBudget;
  }

  /// Handles sql.cancel method (cancels in-flight streaming execution).
  Future<RpcResponse> _handleSqlCancel(RpcRequest request) async {
    if (!_featureFlags.enableSocketCancelMethod) {
      return _methodNotFound(request);
    }

    final gateway = _streamingGateway;
    if (gateway == null) {
      return _executionNotFound(request);
    }

    if (request.params != null && request.params is! Map<String, dynamic>) {
      return _invalidParams(request, 'params must be an object');
    }

    final params = request.params as Map<String, dynamic>? ?? {};
    final executionId = params['execution_id'] as String?;
    final requestId = params['request_id'] as String?;

    if ((executionId == null || executionId.isEmpty) && (requestId == null || requestId.isEmpty)) {
      return _invalidParams(
        request,
        'At least one of execution_id or request_id is required',
      );
    }

    final activeExecution = _activeStreamExecution;
    if (!gateway.hasActiveStream || activeExecution == null) {
      return _executionNotFound(request);
    }

    if (!_matchesActiveExecution(
      executionId: executionId,
      requestId: requestId,
      activeExecution: activeExecution,
    )) {
      return _executionNotFound(request);
    }

    final cancelResult = await gateway.cancelActiveStream(
      executionId: activeExecution.executionId,
    );

    return cancelResult.fold(
      (_) {
        final resultData = <String, dynamic>{
          'cancelled': true,
          ...?(executionId != null ? {'execution_id': executionId} : null),
          ...?(requestId != null ? {'request_id': requestId} : null),
        };
        return RpcResponse.success(id: request.id, result: resultData);
      },
      (failure) {
        final rpcError = FailureToRpcErrorMapper.map(
          failure as domain.Failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      },
    );
  }

  Future<RpcResponse> _handleAgentGetProfile(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    // Params structure and allowed keys are validated upstream by
    // RpcRequestSchemaValidator before dispatch reaches this method.

    final deadline = _featureFlags.enableSocketTimeoutByStage
        ? DateTime.now().add(_authorizationStageBudgetDuration)
        : null;

    if (_featureFlags.enableClientTokenAuthorization && (clientToken == null || clientToken.isEmpty)) {
      final rpcError = FailureToRpcErrorMapper.map(
        _buildMissingClientTokenFailure(),
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    if (_featureFlags.enableClientTokenAuthorization && clientToken != null && clientToken.isNotEmpty) {
      final authResult = await _authorizeWithBudget(
        token: clientToken,
        sql: _agentProfileAuthorizationSql,
        requestId: request.id?.toString(),
        method: request.method,
        deadline: deadline,
      );
      if (authResult.isError()) {
        final failure = authResult.exceptionOrNull()! as domain.Failure;
        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      }
    }

    final repository = _configRepository;
    if (repository == null) {
      return _internalError(
        request,
        'Agent profile repository is not available',
      );
    }

    final result = await repository.getCurrentConfig();
    if (result.isError()) {
      final failure = result.exceptionOrNull()! as domain.Failure;
      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final config = result.getOrThrow();
    final profileResult = AgentProfile.fromConfig(config);
    if (profileResult.isError()) {
      final failure = profileResult.exceptionOrNull()! as domain.Failure;
      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final profile = profileResult.getOrThrow();
    final payload = <String, dynamic>{
      'agent_id': agentId,
      'profile': profile.toJson(),
      'updated_at': config.updatedAt.toUtc().toIso8601String(),
      if (_odbcNativeMetricsService != null) 'odbc': await _collectOdbcDiagnosticsPayload(),
    };
    return RpcResponse.success(
      id: request.id,
      result: payload,
    );
  }

  Future<RpcResponse> _handleAgentGetHealth(
    RpcRequest request,
    String? clientToken,
  ) async {
    final deadline = _featureFlags.enableSocketTimeoutByStage
        ? DateTime.now().add(_authorizationStageBudgetDuration)
        : null;

    if (_featureFlags.enableClientTokenAuthorization && (clientToken == null || clientToken.isEmpty)) {
      final rpcError = FailureToRpcErrorMapper.map(
        _buildMissingClientTokenFailure(),
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    if (_featureFlags.enableClientTokenAuthorization && clientToken != null && clientToken.isNotEmpty) {
      final authResult = await _authorizeWithBudget(
        token: clientToken,
        sql: _agentProfileAuthorizationSql,
        requestId: request.id?.toString(),
        method: request.method,
        deadline: deadline,
      );
      if (authResult.isError()) {
        final failure = authResult.exceptionOrNull()! as domain.Failure;
        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      }
    }

    final raw = _healthService.getHealthStatus();
    final result = json.decode(json.encode(raw)) as Map<String, dynamic>;
    return RpcResponse.success(
      id: request.id,
      result: result,
    );
  }

  Future<RpcResponse> _handleClientTokenGetPolicy(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    if (!_featureFlags.enableClientTokenAuthorization) {
      return _invalidParams(
        request,
        'client_token.getPolicy requires enableClientTokenAuthorization',
        rpcReason: 'client_token_authorization_disabled',
      );
    }

    if (!_featureFlags.enableClientTokenPolicyIntrospection) {
      return _invalidParams(
        request,
        'client_token.getPolicy requires enableClientTokenPolicyIntrospection',
        rpcReason: 'client_token_introspection_disabled',
      );
    }

    if (clientToken == null || clientToken.isEmpty) {
      final rpcError = FailureToRpcErrorMapper.map(
        _buildMissingClientTokenFailure(),
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final scopeKey = '$agentId:${hashClientCredentialToken(clientToken)}';
    if (!_getPolicyRateLimiter.tryAcquire(scopeKey)) {
      _dispatchMetrics?.recordClientTokenGetPolicyRateLimited();
      return _clientTokenGetPolicyRateLimited(request);
    }

    final policyResult = await _getClientTokenPolicy.call(clientToken);
    return policyResult.fold(
      (ClientTokenPolicy policy) {
        _dispatchMetrics?.recordClientTokenGetPolicySuccess();
        return RpcResponse.success(
          id: request.id,
          result: policy.toRpcResultJson(),
        );
      },
      (Object failure) {
        final domainFailure = failure is domain.Failure
            ? failure
            : domain.ServerFailure.withContext(
                message: 'Unexpected error while resolving client token policy',
                context: {'unexpected_type': failure.runtimeType.toString()},
              );
        _dispatchMetrics?.recordClientTokenGetPolicyFailure(domainFailure);
        if (failure is! domain.Failure) {
          developer.log(
            'client_token.getPolicy unexpected failure type',
            name: 'rpc_method_dispatcher',
            level: 500,
            error: failure is Exception ? failure : null,
          );
        }
        final rpcError = FailureToRpcErrorMapper.map(
          domainFailure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      },
    );
  }

  RpcResponse _clientTokenGetPolicyRateLimited(RpcRequest request) {
    const code = RpcErrorCode.rateLimited;
    final window = _clientTokenGetPolicyRateLimitWindowFields();
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: 'client_token.getPolicy rate limit exceeded for this agent and credential',
          correlationId: request.id?.toString(),
          reason: 'client_token_get_policy_rate_limited',
          extra: {
            'method': request.method,
            'retry_after_ms': window['retry_after_ms'],
            'reset_at': window['reset_at'],
          },
        ),
      ),
    );
  }

  /// Next UTC minute boundary for the fixed window used by the getPolicy rate limiter.
  Map<String, dynamic> _clientTokenGetPolicyRateLimitWindowFields() {
    final ms = DateTime.now().toUtc().millisecondsSinceEpoch;
    final windowEndMs = ((ms ~/ 60000) + 1) * 60000;
    final retryAfterMs = windowEndMs - ms;
    final resetAt = DateTime.fromMillisecondsSinceEpoch(windowEndMs, isUtc: true).toIso8601String();
    return <String, dynamic>{
      'retry_after_ms': retryAfterMs,
      'reset_at': resetAt,
    };
  }

  Future<Map<String, dynamic>> _collectOdbcDiagnosticsPayload() async {
    final metricsService = _odbcNativeMetricsService;
    if (metricsService == null) {
      return const <String, dynamic>{'available': false};
    }

    final snapshotResult = await metricsService.collectSnapshot();
    return snapshotResult.fold(
      (snapshot) => <String, dynamic>{
        'available': true,
        'snapshot': snapshot,
      },
      (failure) => <String, dynamic>{
        'available': false,
        'error': failure.toString(),
      },
    );
  }

  /// Returns execution not found error for sql.cancel.
  RpcResponse _executionNotFound(RpcRequest request) {
    const code = RpcErrorCode.executionNotFound;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage:
              'No in-flight execution found to cancel. '
              'Execution may have completed or never started.',
          correlationId: request.id?.toString(),
          extra: {'method': 'sql.cancel'},
        ),
      ),
    );
  }

  /// Returns a method not found error.
  RpcResponse _methodNotFound(RpcRequest request) {
    const code = RpcErrorCode.methodNotFound;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: 'RPC method not found: ${request.method}',
          correlationId: request.id?.toString(),
          extra: {
            'method': request.method,
          },
        ),
      ),
    );
  }

  /// Returns an invalid params error.
  RpcResponse _invalidParams(
    RpcRequest request,
    String detail, {
    String? rpcReason,
    Map<String, dynamic> extraFields = const <String, dynamic>{},
  }) {
    const code = RpcErrorCode.invalidParams;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: detail,
          correlationId: request.id?.toString(),
          reason: rpcReason ?? RpcErrorCode.getReason(code),
          extra: <String, dynamic>{
            'detail': detail,
            'method': request.method,
            ...extraFields,
          },
        ),
      ),
    );
  }

  /// Returns an internal server error (-32603).
  ///
  /// Use for server-side conditions the client cannot fix, such as a missing
  /// repository or an unexpected runtime state.
  RpcResponse _internalError(RpcRequest request, String detail) {
    const code = RpcErrorCode.internalError;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: detail,
          correlationId: request.id?.toString(),
          extra: {'detail': detail},
        ),
      ),
    );
  }

  RpcResponse? _consumeIdempotentCacheIfAny(
    RpcRequest request,
    String? idempotencyKey,
    String idempotencyFingerprint,
  ) {
    if (request.isNotification ||
        !_featureFlags.enableSocketIdempotency ||
        idempotencyKey == null ||
        idempotencyKey.isEmpty) {
      return null;
    }
    final store = _idempotencyStore;
    if (store == null) {
      return null;
    }
    final cachedRecord = store.getRecord(idempotencyKey);
    if (cachedRecord != null &&
        cachedRecord.requestFingerprint != null &&
        cachedRecord.requestFingerprint != idempotencyFingerprint) {
      _onIdempotencyFingerprintMismatch?.call();
      return _invalidParams(
        request,
        'idempotency_key was already used with a different request payload',
      );
    }
    final cached = cachedRecord?.response;
    if (cached != null) {
      return RpcResponse(
        jsonrpc: cached.jsonrpc,
        id: request.id,
        result: cached.result,
        error: cached.error,
        apiVersion: cached.apiVersion,
        meta: cached.meta,
      );
    }
    return null;
  }

  void _storeIdempotentSuccessIfApplicable({
    required RpcRequest request,
    required String? idempotencyKey,
    required String idempotencyFingerprint,
    required RpcResponse response,
  }) {
    if (request.isNotification ||
        !_featureFlags.enableSocketIdempotency ||
        idempotencyKey == null ||
        idempotencyKey.isEmpty) {
      return;
    }
    final store = _idempotencyStore;
    if (store == null) {
      return;
    }
    store.set(
      idempotencyKey,
      response,
      _idempotencyTtl,
      requestFingerprint: idempotencyFingerprint,
    );
  }

  domain.ConfigurationFailure _buildMissingClientTokenFailure() {
    return domain.ConfigurationFailure.withContext(
      message: 'Client token is required for authorized SQL operations',
      context: {
        'authentication': true,
        'reason': 'missing_client_token',
      },
    );
  }

  String _authorizationFingerprint(String sql) {
    return sql.trim().replaceAll(_authorizationSqlWhitespaceCollapse, ' ').toLowerCase();
  }

  int _resolveMaxRows(Map<String, dynamic> params, int negotiatedMaxRows) {
    final options = params['options'] as Map<String, dynamic>?;
    final requestedMaxRows = jsonPositiveInt(options?['max_rows']);
    if (requestedMaxRows == null) {
      return negotiatedMaxRows;
    }
    return requestedMaxRows < negotiatedMaxRows ? requestedMaxRows : negotiatedMaxRows;
  }

  bool _resolveMultiResult(Map<String, dynamic> params) {
    final options = params['options'] as Map<String, dynamic>?;
    return options?['multi_result'] == true;
  }

  _ResolvedSqlHandlingMode _resolveSqlHandlingMode(
    Map<String, dynamic> params,
  ) {
    final options = params['options'] as Map<String, dynamic>?;
    if (options == null) {
      return const _ResolvedSqlHandlingMode(
        sqlHandlingMode: SqlHandlingMode.managed,
      );
    }

    final executionMode = options['execution_mode'];
    if (executionMode != null && executionMode is! String) {
      return const _ResolvedSqlHandlingMode(
        errorMessage: 'execution_mode must be a string',
      );
    }
    if (executionMode != null && executionMode != 'managed' && executionMode != 'preserve') {
      return const _ResolvedSqlHandlingMode(
        errorMessage: 'execution_mode must be "managed" or "preserve"',
      );
    }

    final preserveSql = options['preserve_sql'];
    if (preserveSql != null && preserveSql is! bool) {
      return const _ResolvedSqlHandlingMode(
        errorMessage: 'preserve_sql must be a boolean',
      );
    }
    if (preserveSql == true && executionMode == 'managed') {
      return const _ResolvedSqlHandlingMode(
        errorMessage: 'preserve_sql cannot be true when execution_mode is "managed"',
      );
    }

    if (preserveSql == true) {
      AppLogger.warning(
        'options.preserve_sql is deprecated; use options.execution_mode: '
        '"preserve" instead',
      );
    }

    final resolvedMode = executionMode == 'preserve' || preserveSql == true
        ? SqlHandlingMode.preserve
        : SqlHandlingMode.managed;
    final hasManagedPagination = options['page'] != null || options['page_size'] != null || options['cursor'] != null;
    if (resolvedMode == SqlHandlingMode.preserve && hasManagedPagination) {
      return const _ResolvedSqlHandlingMode(
        errorMessage: 'execution_mode "preserve" cannot be combined with page, page_size, or cursor',
      );
    }

    return _ResolvedSqlHandlingMode(sqlHandlingMode: resolvedMode);
  }

  _ResolvedPagination _resolvePagination(
    Map<String, dynamic> params,
    String sql,
    int negotiatedMaxRows,
    Map<String, dynamic> negotiatedExtensions,
  ) {
    final options = params['options'] as Map<String, dynamic>?;
    final page = jsonPositiveInt(options?['page']);
    final pageSize = jsonPositiveInt(options?['page_size']);
    final cursor = options?['cursor'] as String?;
    if (page == null && pageSize == null && cursor == null) {
      return const _ResolvedPagination();
    }

    final paginationPlanResult = SqlValidator.validatePaginationQuery(sql);
    SqlPaginationPlan? plan;
    if (paginationPlanResult.isSuccess()) {
      plan = paginationPlanResult.getOrNull();
    } else {
      final failure = paginationPlanResult.exceptionOrNull()! as domain.Failure;
      final isMissingOrderBy = failure.message == 'Paginated queries must declare an explicit ORDER BY clause';
      if (cursor != null || !isMissingOrderBy) {
        return _ResolvedPagination(errorMessage: failure.message);
      }
    }

    if (cursor != null) {
      final stablePlan = plan;
      if (stablePlan == null) {
        return const _ResolvedPagination(
          errorMessage: 'Cursor pagination requires an explicit ORDER BY clause',
        );
      }
      if (page != null || pageSize != null) {
        return const _ResolvedPagination(
          errorMessage: 'cursor cannot be combined with page or page_size',
        );
      }
      if (!_supportsCursorKeysetPagination(negotiatedExtensions)) {
        return const _ResolvedPagination(
          errorMessage: 'Negotiated protocol does not allow cursor pagination',
        );
      }

      try {
        final decodedCursor = QueryPaginationCursor.fromToken(cursor);
        if (decodedCursor.pageSize > negotiatedMaxRows) {
          return _ResolvedPagination(
            errorMessage:
                'cursor page_size exceeds negotiated limit: '
                '${decodedCursor.pageSize} > $negotiatedMaxRows',
          );
        }
        if (decodedCursor.isStableCursor) {
          if (decodedCursor.queryHash != stablePlan.queryFingerprint) {
            return const _ResolvedPagination(
              errorMessage: 'cursor does not match the SQL query fingerprint',
            );
          }
          if (!_orderByMatchesPlan(decodedCursor.orderBy, stablePlan.orderBy)) {
            return const _ResolvedPagination(
              errorMessage: 'cursor ordering does not match the SQL ORDER BY',
            );
          }
        }

        return _ResolvedPagination(
          pagination: QueryPaginationRequest(
            page: decodedCursor.page,
            pageSize: decodedCursor.pageSize,
            cursor: cursor,
            offset: decodedCursor.offset,
            queryHash: decodedCursor.queryHash ?? stablePlan.queryFingerprint,
            orderBy: stablePlan.orderBy,
            lastRowValues: decodedCursor.lastRowValues,
          ),
        );
      } on Exception catch (e, stackTrace) {
        developer.log(
          'Pagination cursor parsing failed (invalid or malformed)',
          name: 'rpc_method_dispatcher',
          error: e,
          stackTrace: stackTrace,
        );
        return const _ResolvedPagination(
          errorMessage: 'cursor is invalid or malformed',
        );
      }
    }

    if (page == null || pageSize == null || page < 1 || pageSize < 1) {
      return const _ResolvedPagination(
        errorMessage: 'page and page_size must be provided together and be >= 1',
      );
    }
    if (!_supportsPageOffsetPagination(negotiatedExtensions)) {
      return const _ResolvedPagination(
        errorMessage: 'Negotiated protocol does not allow page-offset pagination',
      );
    }
    if (pageSize > negotiatedMaxRows) {
      return _ResolvedPagination(
        errorMessage:
            'page_size exceeds negotiated limit: '
            '$pageSize > $negotiatedMaxRows',
      );
    }

    return _ResolvedPagination(
      pagination: QueryPaginationRequest(
        page: page,
        pageSize: pageSize,
        queryHash: plan?.queryFingerprint,
        orderBy: plan?.orderBy ?? const [],
      ),
    );
  }

  Map<String, dynamic> _buildPaginationResult(QueryPaginationInfo pagination) {
    return {
      'page': pagination.page,
      'page_size': pagination.pageSize,
      'returned_rows': pagination.returnedRows,
      'has_next_page': pagination.hasNextPage,
      'has_previous_page': pagination.hasPreviousPage,
      if (pagination.currentCursor != null) 'current_cursor': pagination.currentCursor,
      if (pagination.nextCursor != null) 'next_cursor': pagination.nextCursor,
    };
  }

  Map<String, dynamic> _buildExecuteResultData(
    QueryResponse response, {
    required DateTime startedAt,
    required DateTime finishedAt,
    required List<Map<String, dynamic>> limitedRows,
    required bool wasTruncated,
    required SqlHandlingMode sqlHandlingMode,
    required int effectiveMaxRows,
    bool forceMultiResultEnvelope = false,
  }) {
    final resultData = <String, dynamic>{
      'execution_id': response.id,
      'started_at': startedAt.toIso8601String(),
      'finished_at': finishedAt.toIso8601String(),
      'sql_handling_mode': sqlHandlingMode.name,
      'max_rows_handling': 'response_truncation',
      'effective_max_rows': effectiveMaxRows,
      'rows': limitedRows,
      'row_count': limitedRows.length,
    };

    if (response.affectedRows != null) {
      resultData['affected_rows'] = response.affectedRows;
    }
    if (wasTruncated) {
      resultData['truncated'] = true;
    }
    if (response.columnMetadata != null) {
      resultData['column_metadata'] = response.columnMetadata;
    }
    if (response.pagination != null) {
      resultData['pagination'] = _buildPaginationResult(response.pagination!);
    }
    if (forceMultiResultEnvelope || response.hasMultiResult) {
      resultData['multi_result'] = true;
      resultData['result_set_count'] = response.resultSets.length;
      resultData['item_count'] = response.items.length;
      resultData['result_sets'] = response.resultSets.map(_buildResultSetPayload).toList(growable: false);
      resultData['items'] = response.items.map(_buildResponseItemPayload).toList(growable: false);
    }

    return resultData;
  }

  Map<String, dynamic> _buildResultSetPayload(
    QueryResultSet resultSet, {
    bool includeIndex = true,
  }) {
    return {
      if (includeIndex) 'index': resultSet.index,
      'rows': resultSet.rows,
      'row_count': resultSet.rowCount,
      if (resultSet.affectedRows != null) 'affected_rows': resultSet.affectedRows,
      if (resultSet.columnMetadata != null) 'column_metadata': resultSet.columnMetadata,
    };
  }

  Map<String, dynamic> _buildResponseItemPayload(QueryResponseItem item) {
    if (item.resultSet != null) {
      return {
        'type': 'result_set',
        'index': item.index,
        'result_set_index': item.resultSet!.index,
        ..._buildResultSetPayload(item.resultSet!, includeIndex: false),
      };
    }
    return {
      'type': 'row_count',
      'index': item.index,
      'affected_rows': item.rowCount,
    };
  }

  QueryResponse _applyMaxRowsToMultiResultSets(
    QueryResponse response,
    int maxRows,
  ) {
    if (response.resultSets.isEmpty) {
      return response;
    }
    final newSets = <QueryResultSet>[];
    for (final rs in response.resultSets) {
      final limited = truncateSqlResultRows(rs.rows, maxRows);
      newSets.add(
        QueryResultSet(
          index: rs.index,
          rows: limited,
          rowCount: limited.length,
          affectedRows: rs.affectedRows,
          columnMetadata: rs.columnMetadata,
        ),
      );
    }
    final newItems = response.items
        .map((QueryResponseItem item) {
          if (item.resultSet != null) {
            final idx = item.resultSet!.index;
            final match = newSets.firstWhere(
              (QueryResultSet s) => s.index == idx,
            );
            return QueryResponseItem.resultSet(
              index: item.index,
              resultSet: match,
            );
          }
          return item;
        })
        .toList(growable: false);
    final primary = newSets.isNotEmpty ? newSets.first : const QueryResultSet(index: 0, rows: [], rowCount: 0);
    return QueryResponse(
      id: response.id,
      requestId: response.requestId,
      agentId: response.agentId,
      data: primary.rows,
      affectedRows: response.affectedRows,
      timestamp: response.timestamp,
      error: response.error,
      columnMetadata: primary.columnMetadata,
      pagination: response.pagination,
      resultSets: newSets,
      items: newItems,
    );
  }

  bool _multiResultSetsWereTruncated(
    QueryResponse before,
    QueryResponse after,
  ) {
    if (before.resultSets.length != after.resultSets.length) {
      return true;
    }
    for (var i = 0; i < before.resultSets.length; i++) {
      if (before.resultSets[i].rows.length != after.resultSets[i].rows.length) {
        return true;
      }
    }
    return false;
  }

  bool _matchesActiveExecution({
    required String? executionId,
    required String? requestId,
    required _ActiveStreamExecution activeExecution,
  }) {
    final executionMatches = executionId != null && executionId == activeExecution.executionId;
    final requestMatches = requestId != null && requestId == activeExecution.requestId;
    return executionMatches || requestMatches;
  }

  bool _supportsPageOffsetPagination(
    Map<String, dynamic> negotiatedExtensions,
  ) {
    final modes = _negotiatedPaginationModes(negotiatedExtensions);
    return modes.contains('page-offset');
  }

  bool _supportsCursorKeysetPagination(
    Map<String, dynamic> negotiatedExtensions,
  ) {
    final modes = _negotiatedPaginationModes(negotiatedExtensions);
    return modes.contains('cursor-keyset') || modes.contains('cursor-offset');
  }

  Set<String> _negotiatedPaginationModes(
    Map<String, dynamic> negotiatedExtensions,
  ) {
    final rawModes = negotiatedExtensions['paginationModes'];
    if (rawModes is! List<dynamic> || rawModes.isEmpty) {
      return {'page-offset', 'cursor-keyset'};
    }
    return rawModes.whereType<String>().toSet();
  }

  bool _orderByMatchesPlan(
    List<QueryPaginationOrderTerm> cursorOrderBy,
    List<QueryPaginationOrderTerm> planOrderBy,
  ) {
    if (cursorOrderBy.length != planOrderBy.length) {
      return false;
    }

    for (var i = 0; i < cursorOrderBy.length; i++) {
      final left = cursorOrderBy[i];
      final right = planOrderBy[i];
      if (left.expression != right.expression ||
          left.lookupKey != right.lookupKey ||
          left.descending != right.descending) {
        return false;
      }
    }
    return true;
  }

  /// Emits `rpc:complete` with [status] so the hub can deterministically close
  /// a stream that ended without full success.
  ///
  /// Swallows emit errors and records a failure counter so the caller can
  /// return the RPC error response even when the terminal complete fails.
  Future<void> _emitTerminalComplete({
    required IRpcStreamEmitter streamEmitter,
    required String streamId,
    required dynamic requestId,
    required int totalRows,
    required StreamTerminalStatus status,
  }) async {
    try {
      await streamEmitter.emitComplete(
        RpcStreamComplete(
          streamId: streamId,
          requestId: requestId,
          totalRows: totalRows,
          terminalStatus: status,
        ),
      );
      _dispatchMetrics?.recordStreamTerminalCompleteEmitted();
    } on Object catch (error, stackTrace) {
      _dispatchMetrics?.recordStreamTerminalCompleteFailed();
      developer.log(
        'Failed to emit terminal rpc:complete '
        'stream_id=$streamId status=${status.name}',
        name: 'rpc.dispatcher',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

class _ResolvedPagination {
  const _ResolvedPagination({
    this.pagination,
    this.errorMessage,
  });

  final QueryPaginationRequest? pagination;
  final String? errorMessage;

  bool get hasError => errorMessage != null;
}

class _ResolvedSqlHandlingMode {
  const _ResolvedSqlHandlingMode({
    this.sqlHandlingMode,
    this.errorMessage,
  });

  final SqlHandlingMode? sqlHandlingMode;
  final String? errorMessage;

  bool get hasError => errorMessage != null;
}

class _BatchCommandExecutionPlan {
  const _BatchCommandExecutionPlan({
    required this.command,
    required this.requestIndex,
    required this.executionOrder,
  });

  final SqlCommand command;
  final int requestIndex;
  final int? executionOrder;
}

class _ActiveStreamExecution {
  const _ActiveStreamExecution({
    required this.streamId,
    required this.executionId,
    required this.requestId,
  });

  final String streamId;
  final String executionId;
  final String? requestId;
}
