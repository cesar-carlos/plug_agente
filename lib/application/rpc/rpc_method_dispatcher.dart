import 'dart:async';

import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/execute_sql_batch.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/infrastructure/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/infrastructure/metrics/authorization_metrics.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

/// RPC method dispatcher for routing JSON-RPC requests to handlers.
class RpcMethodDispatcher {
  RpcMethodDispatcher({
    required IDatabaseGateway databaseGateway,
    required QueryNormalizerService normalizerService,
    required Uuid uuid,
    required AuthorizeSqlOperation authorizeSqlOperation,
    required FeatureFlags featureFlags,
    IAgentConfigRepository? configRepository,
    IIdempotencyStore? idempotencyStore,
    AuthorizationMetricsCollector? authMetrics,
    IStreamingDatabaseGateway? streamingGateway,
    TransportLimits defaultLimits = const TransportLimits(),
    Duration sqlExecuteTotalBudget = _defaultSqlExecuteTotalBudget,
    Duration sqlBatchTotalBudget = _defaultSqlBatchTotalBudget,
    Duration authorizationStageBudget = _defaultAuthorizationStageBudget,
    Duration queryStageBudget = _defaultQueryStageBudget,
    Duration batchExecutionStageBudget = _defaultBatchExecutionStageBudget,
  }) : _databaseGateway = databaseGateway,
       _normalizerService = normalizerService,
       _uuid = uuid,
       _authorizeSqlOperation = authorizeSqlOperation,
       _featureFlags = featureFlags,
       _configRepository = configRepository,
       _idempotencyStore = idempotencyStore,
       _authMetrics = authMetrics,
       _streamingGateway = streamingGateway,
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
  final QueryNormalizerService _normalizerService;
  final Uuid _uuid;
  final AuthorizeSqlOperation _authorizeSqlOperation;
  final FeatureFlags _featureFlags;
  final IAgentConfigRepository? _configRepository;
  final IIdempotencyStore? _idempotencyStore;
  final AuthorizationMetricsCollector? _authMetrics;
  final IStreamingDatabaseGateway? _streamingGateway;
  final TransportLimits _defaultLimits;
  final Duration _sqlExecuteTotalBudgetDuration;
  final Duration _sqlBatchTotalBudgetDuration;
  final Duration _authorizationStageBudgetDuration;
  final Duration _queryStageBudgetDuration;
  final Duration _batchExecutionStageBudgetDuration;

  static const _idempotencyTtl = Duration(minutes: 5);
  static const _defaultSqlExecuteTotalBudget = Duration(seconds: 35);
  static const _defaultSqlBatchTotalBudget = Duration(seconds: 45);
  static const _defaultAuthorizationStageBudget = Duration(seconds: 3);
  static const _defaultQueryStageBudget = Duration(seconds: 30);
  static const _defaultBatchExecutionStageBudget = Duration(seconds: 35);
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
      _ => _methodNotFound(request),
    };
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
    final sql = params['sql'] as String?;
    final maxRows = _resolveMaxRows(params, limits.maxRows);
    final deadline = _featureFlags.enableSocketTimeoutByStage
        ? DateTime.now().add(_sqlExecuteTotalBudgetDuration)
        : null;

    if (sql == null || sql.isEmpty) {
      return _invalidParams(request, 'sql is required');
    }
    final paginationResolution = _resolvePagination(
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
    final requestParameters = params['params'] as Map<String, dynamic>?;

    if (multiResultRequested &&
        requestParameters != null &&
        requestParameters.isNotEmpty) {
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

    final idempotencyKey = params['idempotency_key'] as String?;
    final store = _idempotencyStore;
    if (!request.isNotification &&
        _featureFlags.enableSocketIdempotency &&
        store != null &&
        idempotencyKey != null &&
        idempotencyKey.isNotEmpty) {
      final cached = store.get(idempotencyKey);
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
    }

    if (_featureFlags.enableClientTokenAuthorization &&
        (clientToken == null || clientToken.isEmpty)) {
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

    if (_featureFlags.enableClientTokenAuthorization &&
        clientToken != null &&
        clientToken.isNotEmpty) {
      final authStopwatch = Stopwatch()..start();
      final authResult = await _authorizeWithBudget(
        token: clientToken,
        sql: sql,
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
      requestId: request.id?.toString(),
      deadline: deadline,
    );

    return result.fold<Future<RpcResponse>>(
      (QueryResponse queryResponse) async {
        // Normalize
        final normalized = await _normalizerService.normalize(queryResponse);

        final limitedRows = _applyMaxRows(normalized.data, maxRows);
        final wasTruncated = limitedRows.length != normalized.data.length;
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

          for (var i = 0; i < rows.length; i += limits.streamingChunkSize) {
            final chunkRows = rows
                .skip(i)
                .take(limits.streamingChunkSize)
                .toList();
            streamEmitter.emitChunk(
              RpcStreamChunk(
                streamId: streamId,
                requestId: request.id,
                chunkIndex: i ~/ limits.streamingChunkSize,
                rows: chunkRows,
                totalChunks: totalChunks,
                columnMetadata: normalized.columnMetadata,
              ),
            );
          }

          streamEmitter.emitComplete(
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
            'rows': <Map<String, dynamic>>[],
            'row_count': 0,
            'affected_rows': normalized.affectedRows,
            'returned_rows': rows.length,
            if (wasTruncated) 'truncated': true,
            if (normalized.columnMetadata != null)
              'column_metadata': normalized.columnMetadata,
            if (normalized.pagination != null)
              'pagination': _buildPaginationResult(normalized.pagination!),
          };

          return RpcResponse.success(id: request.id, result: resultData);
        }

        final resultData = _buildExecuteResultData(
          normalized,
          startedAt: queryRequest.timestamp,
          finishedAt: normalized.timestamp,
          limitedRows: limitedRows,
          wasTruncated: wasTruncated,
          forceMultiResultEnvelope: multiResultRequested,
        );

        final rpcResponse = RpcResponse.success(
          id: request.id,
          result: resultData,
        );
        if (!request.isNotification &&
            _featureFlags.enableSocketIdempotency &&
            store != null &&
            idempotencyKey != null &&
            idempotencyKey.isNotEmpty) {
          store.set(
            idempotencyKey,
            rpcResponse,
            _idempotencyTtl,
          );
        }
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
        (chunk) {
          if (columnMetadata == null && chunk.isNotEmpty) {
            columnMetadata = chunk.first.keys
                .map((k) => <String, dynamic>{'name': k, 'type': 'string'})
                .toList();
          }
          totalRows += chunk.length;
          streamEmitter.emitChunk(
            RpcStreamChunk(
              streamId: streamId,
              requestId: request.id,
              chunkIndex: chunkIndex++,
              rows: chunk,
              columnMetadata: columnMetadata,
            ),
          );
        },
        fetchSize: limits.streamingChunkSize,
      );

      return streamResult.fold(
        (_) {
          streamEmitter.emitComplete(
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
          return RpcResponse.success(
            id: request.id,
            result: {
              'stream_id': streamId,
              'execution_id': executionId,
              'started_at': queryRequest.timestamp.toIso8601String(),
              'finished_at': DateTime.now().toUtc().toIso8601String(),
              'rows': <Map<String, dynamic>>[],
              'row_count': 0,
              'affected_rows': totalRows,
              ...?(columnMetadata != null
                  ? {'column_metadata': columnMetadata}
                  : null),
            },
          );
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
    final deadline = _featureFlags.enableSocketTimeoutByStage
        ? DateTime.now().add(_sqlBatchTotalBudgetDuration)
        : null;
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
    final store = _idempotencyStore;
    if (!request.isNotification &&
        _featureFlags.enableSocketIdempotency &&
        store != null &&
        idempotencyKey != null &&
        idempotencyKey.isNotEmpty) {
      final cached = store.get(idempotencyKey);
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
    }

    // Parse commands
    final commands = commandsJson
        .map((c) => SqlCommand.fromJson(c as Map<String, dynamic>))
        .toList();

    if (_featureFlags.enableClientTokenAuthorization &&
        (clientToken == null || clientToken.isEmpty)) {
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

    if (_featureFlags.enableClientTokenAuthorization &&
        clientToken != null &&
        clientToken.isNotEmpty) {
      for (final cmd in commands) {
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
      }
    }

    // Parse options
    final optionsJson = params['options'] as Map<String, dynamic>?;
    final options = optionsJson != null
        ? SqlExecutionOptions.fromJson(optionsJson)
        : const SqlExecutionOptions();
    final effectiveOptions = SqlExecutionOptions(
      timeoutMs: options.timeoutMs,
      maxRows: options.maxRows < limits.maxRows
          ? options.maxRows
          : limits.maxRows,
      transaction: options.transaction,
    );

    // Execute batch
    final database = params['database'] as String?;
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
        final resultData = {
          'execution_id': _uuid.v4(),
          'started_at': DateTime.now().toIso8601String(),
          'finished_at': DateTime.now().toIso8601String(),
          'items': commandResults.map((r) => r.toJson()).toList(),
          'total_commands': commands.length,
          'successful_commands': commandResults.where((r) => r.ok).length,
          'failed_commands': commandResults.where((r) => !r.ok).length,
        };

        final response = RpcResponse.success(
          id: request.id,
          result: resultData,
        );
        if (!request.isNotification &&
            _featureFlags.enableSocketIdempotency &&
            store != null &&
            idempotencyKey != null &&
            idempotencyKey.isNotEmpty) {
          store.set(
            idempotencyKey,
            response,
            _idempotencyTtl,
          );
        }
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
    } on TimeoutException {
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
          context: context,
        ),
      );
    }
  }

  Future<Result<QueryResponse>> _executeQueryWithBudget(
    QueryRequest queryRequest, {
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
        return await _databaseGateway.executeQuery(queryRequest);
      }
      return await _databaseGateway.executeQuery(queryRequest).timeout(timeout);
    } on TimeoutException {
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
    final timeout = _effectiveStageTimeout(
      deadline: deadline,
      stageBudget: _batchExecutionStageBudgetDuration,
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
      if (timeout == null) {
        return await _executeSqlBatch(
          agentId,
          commands,
          database: database,
          options: options,
        );
      }
      return await _executeSqlBatch(
        agentId,
        commands,
        database: database,
        options: options,
      ).timeout(timeout);
    } on TimeoutException {
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

    if ((executionId == null || executionId.isEmpty) &&
        (requestId == null || requestId.isEmpty)) {
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

    final cancelResult = await gateway.cancelActiveStream();

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
  RpcResponse _invalidParams(RpcRequest request, String detail) {
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
          extra: {
            'detail': detail,
          },
        ),
      ),
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

  int _resolveMaxRows(Map<String, dynamic> params, int negotiatedMaxRows) {
    final options = params['options'] as Map<String, dynamic>?;
    final requestedMaxRows = options?['max_rows'] as int?;
    if (requestedMaxRows == null || requestedMaxRows < 1) {
      return negotiatedMaxRows;
    }
    return requestedMaxRows < negotiatedMaxRows
        ? requestedMaxRows
        : negotiatedMaxRows;
  }

  bool _resolveMultiResult(Map<String, dynamic> params) {
    final options = params['options'] as Map<String, dynamic>?;
    return options?['multi_result'] == true;
  }

  _ResolvedPagination _resolvePagination(
    Map<String, dynamic> params,
    String sql,
    int negotiatedMaxRows,
    Map<String, dynamic> negotiatedExtensions,
  ) {
    final options = params['options'] as Map<String, dynamic>?;
    final page = options?['page'] as int?;
    final pageSize = options?['page_size'] as int?;
    final cursor = options?['cursor'] as String?;
    if (page == null && pageSize == null && cursor == null) {
      return const _ResolvedPagination();
    }

    final paginationPlan = SqlValidator.validatePaginationQuery(sql);
    if (paginationPlan.isError()) {
      final failure = paginationPlan.exceptionOrNull()! as domain.Failure;
      return _ResolvedPagination(errorMessage: failure.message);
    }

    final plan = paginationPlan.getOrNull()!;
    if (cursor != null) {
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
          if (decodedCursor.queryHash != plan.queryFingerprint) {
            return const _ResolvedPagination(
              errorMessage: 'cursor does not match the SQL query fingerprint',
            );
          }
          if (!_orderByMatchesPlan(decodedCursor.orderBy, plan.orderBy)) {
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
            queryHash: decodedCursor.queryHash ?? plan.queryFingerprint,
            orderBy: plan.orderBy,
            lastRowValues: decodedCursor.lastRowValues,
          ),
        );
      } on Exception {
        return const _ResolvedPagination(
          errorMessage: 'cursor is invalid or malformed',
        );
      }
    }

    if (page == null || pageSize == null || page < 1 || pageSize < 1) {
      return const _ResolvedPagination(
        errorMessage:
            'page and page_size must be provided together and be >= 1',
      );
    }
    if (!_supportsPageOffsetPagination(negotiatedExtensions)) {
      return const _ResolvedPagination(
        errorMessage:
            'Negotiated protocol does not allow page-offset pagination',
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
        queryHash: plan.queryFingerprint,
        orderBy: plan.orderBy,
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
      if (pagination.currentCursor != null)
        'current_cursor': pagination.currentCursor,
      if (pagination.nextCursor != null) 'next_cursor': pagination.nextCursor,
    };
  }

  Map<String, dynamic> _buildExecuteResultData(
    QueryResponse response, {
    required DateTime startedAt,
    required DateTime finishedAt,
    required List<Map<String, dynamic>> limitedRows,
    required bool wasTruncated,
    bool forceMultiResultEnvelope = false,
  }) {
    final resultData = <String, dynamic>{
      'execution_id': response.id,
      'started_at': startedAt.toIso8601String(),
      'finished_at': finishedAt.toIso8601String(),
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
      resultData['result_sets'] = response.resultSets
          .map(_buildResultSetPayload)
          .toList(growable: false);
      resultData['items'] = response.items
          .map(_buildResponseItemPayload)
          .toList(growable: false);
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
      if (resultSet.affectedRows != null)
        'affected_rows': resultSet.affectedRows,
      if (resultSet.columnMetadata != null)
        'column_metadata': resultSet.columnMetadata,
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

  List<Map<String, dynamic>> _applyMaxRows(
    List<Map<String, dynamic>> rows,
    int maxRows,
  ) {
    if (rows.length <= maxRows) {
      return rows;
    }
    return rows.take(maxRows).toList();
  }

  bool _matchesActiveExecution({
    required String? executionId,
    required String? requestId,
    required _ActiveStreamExecution activeExecution,
  }) {
    final executionMatches =
        executionId != null && executionId == activeExecution.executionId;
    final requestMatches =
        requestId != null && requestId == activeExecution.requestId;
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
