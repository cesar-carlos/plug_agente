import 'package:plug_agente/application/services/compression_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/execute_sql_batch.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
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
import 'package:uuid/uuid.dart';

/// RPC method dispatcher for routing JSON-RPC requests to handlers.
class RpcMethodDispatcher {
  RpcMethodDispatcher({
    required IDatabaseGateway databaseGateway,
    required QueryNormalizerService normalizerService,
    required CompressionService compressionService,
    required Uuid uuid,
    required AuthorizeSqlOperation authorizeSqlOperation,
    required FeatureFlags featureFlags,
    IAgentConfigRepository? configRepository,
    IIdempotencyStore? idempotencyStore,
    AuthorizationMetricsCollector? authMetrics,
    IStreamingDatabaseGateway? streamingGateway,
  }) : _databaseGateway = databaseGateway,
       _normalizerService = normalizerService,
       _compressionService = compressionService,
       _uuid = uuid,
       _authorizeSqlOperation = authorizeSqlOperation,
       _featureFlags = featureFlags,
       _configRepository = configRepository,
       _idempotencyStore = idempotencyStore,
       _authMetrics = authMetrics,
       _streamingGateway = streamingGateway,
       _executeSqlBatch = ExecuteSqlBatch(
         databaseGateway,
         normalizerService,
         uuid,
       );

  final IDatabaseGateway _databaseGateway;
  final QueryNormalizerService _normalizerService;
  final CompressionService _compressionService;
  final Uuid _uuid;
  final AuthorizeSqlOperation _authorizeSqlOperation;
  final FeatureFlags _featureFlags;
  final IAgentConfigRepository? _configRepository;
  final IIdempotencyStore? _idempotencyStore;
  final AuthorizationMetricsCollector? _authMetrics;
  final IStreamingDatabaseGateway? _streamingGateway;

  static const _idempotencyTtl = Duration(minutes: 5);
  final ExecuteSqlBatch _executeSqlBatch;

  static const int _streamingChunkSize = 500;
  static const int _streamingRowThreshold = 500;

  /// Dispatches an RPC request to the appropriate handler.
  Future<RpcResponse> dispatch(
    RpcRequest request,
    String agentId, {
    String? clientToken,
    IRpcStreamEmitter? streamEmitter,
  }) async {
    return switch (request.method) {
      'sql.execute' => await _handleSqlExecute(
        request,
        agentId,
        clientToken,
        streamEmitter: streamEmitter,
      ),
      'sql.executeBatch' => await _handleSqlExecuteBatch(
        request,
        agentId,
        clientToken,
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
    IRpcStreamEmitter? streamEmitter,
  }) async {
    // Validate params
    if (request.params is! Map<String, dynamic>) {
      return _invalidParams(request, 'params must be an object');
    }

    final params = request.params as Map<String, dynamic>;
    final sql = params['sql'] as String?;

    if (sql == null || sql.isEmpty) {
      return _invalidParams(request, 'sql is required');
    }

    final idempotencyKey = params['idempotency_key'] as String?;
    final store = _idempotencyStore;
    if (_featureFlags.enableSocketIdempotency &&
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
      final authResult = await _authorizeSqlOperation(
        token: clientToken,
        sql: sql,
      );
      if (authResult.isError()) {
        final failure = authResult.exceptionOrNull()! as domain.Failure;
        final ctx = failure.context;
        _authMetrics?.recordDenied(
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
      _authMetrics?.recordAuthorized();
    }

    // Validate SQL (allows SELECT, WITH, UPDATE, INSERT, MERGE, DELETE)
    final validation = SqlValidator.validateSqlForExecution(sql);
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
      parameters: params['params'] as Map<String, dynamic>?,
      timestamp: DateTime.now(),
    );

    final streamingFromDbResponse = await _tryStreamingFromDb(
      request,
      queryRequest,
      sql,
      streamEmitter,
    );
    if (streamingFromDbResponse != null) {
      return streamingFromDbResponse;
    }

    final result = await _databaseGateway.executeQuery(queryRequest);

    return await result.fold(
      (response) async {
        // Normalize
        final normalized = await _normalizerService.normalize(response);

        // Compress
        final compressionResult = await _compressionService.compress(
          normalized,
        );

        return await compressionResult.fold(
          (compressed) async {
            final useStreaming =
                _featureFlags.enableSocketStreamingChunks &&
                streamEmitter != null &&
                compressed.data.length > _streamingRowThreshold;

            if (useStreaming) {
              final streamId = 'stream-${queryRequest.id}';
              final rows = compressed.data;
              final totalChunks = (rows.length / _streamingChunkSize).ceil();

              for (var i = 0; i < rows.length; i += _streamingChunkSize) {
                final chunkRows = rows
                    .skip(i)
                    .take(_streamingChunkSize)
                    .toList();
                streamEmitter.emitChunk(
                  RpcStreamChunk(
                    streamId: streamId,
                    requestId: request.id,
                    chunkIndex: i ~/ _streamingChunkSize,
                    rows: chunkRows,
                    totalChunks: totalChunks,
                    columnMetadata: compressed.columnMetadata,
                  ),
                );
              }

              streamEmitter.emitComplete(
                RpcStreamComplete(
                  streamId: streamId,
                  requestId: request.id,
                  totalRows: rows.length,
                  affectedRows: compressed.affectedRows,
                  executionId: compressed.id,
                  startedAt: queryRequest.timestamp.toIso8601String(),
                  finishedAt: compressed.timestamp.toIso8601String(),
                ),
              );

              final resultData = {
                'stream_id': streamId,
                'execution_id': compressed.id,
                'started_at': queryRequest.timestamp.toIso8601String(),
                'finished_at': compressed.timestamp.toIso8601String(),
                'rows': <Map<String, dynamic>>[],
                'row_count': 0,
                'affected_rows': compressed.affectedRows,
                if (compressed.columnMetadata != null)
                  'column_metadata': compressed.columnMetadata,
              };

              return RpcResponse.success(id: request.id, result: resultData);
            }

            final resultData = {
              'execution_id': compressed.id,
              'started_at': queryRequest.timestamp.toIso8601String(),
              'finished_at': compressed.timestamp.toIso8601String(),
              'rows': compressed.data,
              'row_count': compressed.data.length,
              'affected_rows': compressed.affectedRows,
              if (compressed.columnMetadata != null)
                'column_metadata': compressed.columnMetadata,
            };

            final response = RpcResponse.success(
              id: request.id,
              result: resultData,
            );
            if (_featureFlags.enableSocketIdempotency &&
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
          (failure) {
            final rpcError = FailureToRpcErrorMapper.map(
              failure as domain.Failure,
              instance: request.id?.toString(),
              useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
            );
            return RpcResponse.error(id: request.id, error: rpcError);
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
  }

  /// Tries to stream directly from DB when enabled. Returns null to fall back.
  Future<RpcResponse?> _tryStreamingFromDb(
    RpcRequest request,
    QueryRequest queryRequest,
    String sql,
    IRpcStreamEmitter? streamEmitter,
  ) async {
    if (!_featureFlags.enableSocketStreamingFromDb ||
        !_featureFlags.enableSocketStreamingChunks ||
        streamEmitter == null) {
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
    if (config == null || config.connectionString.trim().isEmpty) {
      return null;
    }

    final streamId = 'stream-${queryRequest.id}';
    var totalRows = 0;
    var chunkIndex = 0;
    List<Map<String, dynamic>>? columnMetadata;

    final streamResult = await gateway.executeQueryStream(
      sql.trim(),
      config.connectionString,
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
    );

    return streamResult.fold(
      (_) {
        final executionId = _uuid.v4();
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
  }

  /// Handles sql.executeBatch method (multiple commands).
  Future<RpcResponse> _handleSqlExecuteBatch(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    // Validate params
    if (request.params is! Map<String, dynamic>) {
      return _invalidParams(request, 'params must be an object');
    }

    final params = request.params as Map<String, dynamic>;
    final commandsJson = params['commands'] as List<dynamic>?;

    if (commandsJson == null || commandsJson.isEmpty) {
      return _invalidParams(
        request,
        'commands is required and must not be empty',
      );
    }

    final idempotencyKey = params['idempotency_key'] as String?;
    final store = _idempotencyStore;
    if (_featureFlags.enableSocketIdempotency &&
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
        final authResult = await _authorizeSqlOperation(
          token: clientToken,
          sql: cmd.sql,
        );
        if (authResult.isError()) {
          final failure = authResult.exceptionOrNull()! as domain.Failure;
          final ctx = failure.context;
          _authMetrics?.recordDenied(
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
        _authMetrics?.recordAuthorized();
      }
    }

    // Parse options
    final optionsJson = params['options'] as Map<String, dynamic>?;
    final options = optionsJson != null
        ? SqlExecutionOptions.fromJson(optionsJson)
        : const SqlExecutionOptions();

    // Execute batch
    final database = params['database'] as String?;
    final result = await _executeSqlBatch(
      agentId,
      commands,
      database: database,
      options: options,
    );

    return result.fold(
      (commandResults) {
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
        if (_featureFlags.enableSocketIdempotency &&
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

    if (!gateway.hasActiveStream) {
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
}
