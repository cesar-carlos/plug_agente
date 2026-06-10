import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/rpc/idempotency_fingerprint.dart';
import 'package:plug_agente/application/rpc/sql_execute_result_mapper.dart';
import 'package:plug_agente/application/rpc/sql_rpc_client_token_gate.dart';
import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/application/rpc/sql_rpc_odbc_budget_runner.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/utils/json_primitive_coercion.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

/// Handles `sql.bulkInsert` RPC requests.
class SqlBulkInsertHandler {
  SqlBulkInsertHandler({
    required FeatureFlags featureFlags,
    required SqlRpcMethodHandlerSupport support,
    required SqlRpcClientTokenGate clientTokenGate,
    required Uuid uuid,
    required SqlRpcOdbcBudgetRunner odbcBudgetRunner,
    required Duration sqlBatchTotalBudget,
  }) : _featureFlags = featureFlags,
       _support = support,
       _clientTokenGate = clientTokenGate,
       _uuid = uuid,
       _odbcBudgetRunner = odbcBudgetRunner,
       _sqlBatchTotalBudgetDuration = sqlBatchTotalBudget;

  static final RegExp _bulkIdentifierPath = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$');

  final FeatureFlags _featureFlags;
  final SqlRpcMethodHandlerSupport _support;
  final SqlRpcClientTokenGate _clientTokenGate;
  final Uuid _uuid;
  final SqlRpcOdbcBudgetRunner _odbcBudgetRunner;
  final Duration _sqlBatchTotalBudgetDuration;

  Future<RpcResponse> handleSqlBulkInsert(
    RpcRequest request,
    String? clientToken, {
    required TransportLimits limits,
  }) async {
    if (request.params is! Map<String, dynamic>) {
      return _support.invalidParams(request, 'params must be an object');
    }

    final params = request.params as Map<String, dynamic>;
    final bulkRequestResult = _parseBulkInsertRequest(request, params, limits);
    if (bulkRequestResult.isError()) {
      final failure = bulkRequestResult.exceptionOrNull()! as domain.Failure;
      return _support.invalidParams(request, failure.message);
    }
    final bulkRequest = bulkRequestResult.getOrThrow();
    final database = params['database'] as String?;
    final authorizationSql = _bulkInsertAuthorizationSql(bulkRequest);
    final deadline = DateTime.now().add(_sqlBatchTotalBudgetDuration);

    final idempotencyKey = params['idempotency_key'] as String?;
    final idempotencyFingerprint = await resolveIdempotencyFingerprint(
      request.method,
      params,
    );
    final idempotentEarly = await _support.consumeIdempotentCacheIfAny(
      request,
      idempotencyKey,
      idempotencyFingerprint,
    );
    if (idempotentEarly != null) {
      return idempotentEarly;
    }

    final bulkAuthDenied = await _clientTokenGate.enforce(
      request: request,
      clientToken: clientToken,
      sqlStatements: [authorizationSql],
      investigationSqlOnDeny: authorizationSql,
      requestDatabase: database,
      deadline: deadline,
    );
    if (bulkAuthDenied != null) {
      return bulkAuthDenied;
    }

    final options = params['options'] as Map<String, dynamic>?;
    final timeoutMs = jsonPositiveInt(options?['timeout_ms']) ?? 0;
    return _support.runIdempotentExecution(
      request: request,
      idempotencyKey: idempotencyKey,
      idempotencyFingerprint: idempotencyFingerprint,
      execute: () async {
        final startedAt = DateTime.now().toUtc();
        final result = await _odbcBudgetRunner.executeBulkInsert(
          bulkRequest,
          database: database,
          timeoutMs: timeoutMs,
          requestId: request.id?.toString(),
          deadline: deadline,
        );

        if (result.isError()) {
          final failure = result.exceptionOrNull()! as domain.Failure;
          final rpcError = FailureToRpcErrorMapper.map(
            failure,
            instance: request.id?.toString(),
            useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
          );
          return RpcResponse.error(id: request.id, error: rpcError);
        }

        final insertedRows = result.getOrThrow();
        final finishedAt = DateTime.now().toUtc();
        return RpcResponse.success(
          id: request.id,
          result: {
            'execution_id': _uuid.v4(),
            'started_at': SqlExecuteResultMapper.executionTimestampUtcIso(startedAt),
            'finished_at': SqlExecuteResultMapper.executionTimestampUtcIso(finishedAt),
            'table': bulkRequest.table,
            'row_count': bulkRequest.rowCount,
            'inserted_rows': insertedRows,
          },
        );
      },
    );
  }

  Result<BulkInsertRequest> _parseBulkInsertRequest(
    RpcRequest request,
    Map<String, dynamic> params,
    TransportLimits limits,
  ) {
    const allowedKeys = {
      'table',
      'columns',
      'rows',
      'client_token',
      'clientToken',
      'auth',
      'idempotency_key',
      'options',
      'database',
    };
    final extraKeys = params.keys.where((key) => !allowedKeys.contains(key));
    if (extraKeys.isNotEmpty) {
      return Failure(
        domain.ValidationFailure(
          'Field "params" contains unsupported properties: ${extraKeys.join(", ")}',
        ),
      );
    }
    try {
      final bulkRequest = BulkInsertRequest.fromJson(params);
      final identifierFailure = _validateBulkInsertIdentifiers(bulkRequest);
      if (identifierFailure != null) {
        return Failure(identifierFailure);
      }
      if (bulkRequest.rows.length > limits.maxRows) {
        return Failure(
          domain.ValidationFailure(
            'Field "params.rows" exceeds negotiated limit: ${bulkRequest.rows.length} > ${limits.maxRows}',
          ),
        );
      }
      final options = params['options'];
      if (options != null && options is! Map<String, dynamic>) {
        return Failure(domain.ValidationFailure('Field "params.options" must be an object'));
      }
      if (options is Map<String, dynamic>) {
        final extraOptionKeys = options.keys.where((key) => key != 'timeout_ms');
        if (extraOptionKeys.isNotEmpty) {
          return Failure(
            domain.ValidationFailure(
              'Field "params.options" contains unsupported properties: ${extraOptionKeys.join(", ")}',
            ),
          );
        }
        final timeout = options['timeout_ms'];
        if (timeout != null && jsonPositiveInt(timeout) == null) {
          return Failure(domain.ValidationFailure('Field "params.options.timeout_ms" must be an integer >= 1'));
        }
      }
      final tokenValidation = _validateBulkInsertTokenAliases(params);
      if (tokenValidation != null) {
        return Failure(tokenValidation);
      }
      final idempotencyKey = params['idempotency_key'];
      if (idempotencyKey != null && (idempotencyKey is! String || idempotencyKey.trim().isEmpty)) {
        return Failure(domain.ValidationFailure('Field "params.idempotency_key" must be a non-empty string'));
      }
      final database = params['database'];
      if (database != null && database is! String) {
        return Failure(domain.ValidationFailure('Field "params.database" must be a string'));
      }
      return Success(bulkRequest);
    } on Object catch (error) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Invalid sql.bulkInsert params',
          cause: error,
          context: {'request_id': ?request.id?.toString()},
        ),
      );
    }
  }

  domain.ValidationFailure? _validateBulkInsertIdentifiers(
    BulkInsertRequest request,
  ) {
    if (!_bulkIdentifierPath.hasMatch(request.table)) {
      return domain.ValidationFailure('Field "params.table" must be a simple identifier path');
    }
    for (final column in request.columns) {
      if (!_bulkIdentifierPath.hasMatch(column.name)) {
        return domain.ValidationFailure('Field "params.columns[].name" must be a simple identifier');
      }
    }
    return null;
  }

  domain.ValidationFailure? _validateBulkInsertTokenAliases(Map<String, dynamic> params) {
    for (final key in ['client_token', 'clientToken', 'auth']) {
      final value = params[key];
      if (value != null && (value is! String || value.trim().isEmpty)) {
        return domain.ValidationFailure('Field "params.$key" must be a non-empty string');
      }
    }
    return null;
  }

  String _bulkInsertAuthorizationSql(BulkInsertRequest request) {
    final columns = request.columns.map((column) => column.name).join(', ');
    return 'INSERT INTO ${request.table} ($columns) VALUES (...)';
  }
}
