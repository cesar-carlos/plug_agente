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
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
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
    AuthorizationMetricsCollector? authMetrics,
  })  : _databaseGateway = databaseGateway,
        _normalizerService = normalizerService,
        _compressionService = compressionService,
        _uuid = uuid,
        _authorizeSqlOperation = authorizeSqlOperation,
        _featureFlags = featureFlags,
        _authMetrics = authMetrics,
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
  final AuthorizationMetricsCollector? _authMetrics;
  final ExecuteSqlBatch _executeSqlBatch;

  /// Dispatches an RPC request to the appropriate handler.
  Future<RpcResponse> dispatch(
    RpcRequest request,
    String agentId, {
    String? clientToken,
  }) async {
    return switch (request.method) {
      'sql.execute' => await _handleSqlExecute(request, agentId, clientToken),
      'sql.executeBatch' =>
        await _handleSqlExecuteBatch(request, agentId, clientToken),
      _ => _methodNotFound(request),
    };
  }

  /// Handles sql.execute method (single command).
  Future<RpcResponse> _handleSqlExecute(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    // Validate params
    if (request.params is! Map<String, dynamic>) {
      return _invalidParams(request, 'params must be an object');
    }

    final params = request.params as Map<String, dynamic>;
    final sql = params['sql'] as String?;

    if (sql == null || sql.isEmpty) {
      return _invalidParams(request, 'sql is required');
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
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    // Execute query
    final queryRequest = QueryRequest(
      id: _uuid.v4(),
      agentId: agentId,
      query: sql,
      parameters: params['params'] as Map<String, dynamic>?,
      timestamp: DateTime.now(),
    );

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

            return RpcResponse.success(id: request.id, result: resultData);
          },
          (failure) {
            final rpcError = FailureToRpcErrorMapper.map(
              failure as domain.Failure,
              instance: request.id?.toString(),
            );
            return RpcResponse.error(id: request.id, error: rpcError);
          },
        );
      },
      (failure) {
        final rpcError = FailureToRpcErrorMapper.map(
          failure as domain.Failure,
          instance: request.id?.toString(),
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

    // Parse commands
    final commands = commandsJson
        .map((c) => SqlCommand.fromJson(c as Map<String, dynamic>))
        .toList();

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

        return RpcResponse.success(id: request.id, result: resultData);
      },
      (failure) {
        final rpcError = FailureToRpcErrorMapper.map(
          failure as domain.Failure,
          instance: request.id?.toString(),
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      },
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
}
