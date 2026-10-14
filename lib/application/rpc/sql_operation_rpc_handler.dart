import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/application/rpc/sql_operation_params_reader.dart';
import 'package:plug_agente/application/services/sql_operation_executor.dart';
import 'package:plug_agente/domain/entities/sql_operation_journal_entry.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/protocol/sql_operation_capability.dart';
import 'package:result_dart/result_dart.dart';

class SqlOperationRpcHandler implements RpcMethodHandler {
  const SqlOperationRpcHandler(this.method, this._executor, {required bool Function() enabled}) : _enabled = enabled;
  final bool Function() _enabled;
  @override
  final String method;
  final SqlOperationExecutor _executor;
  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) async {
    try {
      if (request.id == null) return _error(request, 'SQL_OPERATION_INVALID', RpcErrorCode.invalidRequest);
      if (request.params is Map &&
          (request.params as Map).containsKey('expectedSource') &&
          context.negotiatedExtensions['sourceIdentity'] != 1) {
        return _error(request, 'CAPABILITY_UNAVAILABLE');
      }
      final capability = context.negotiatedExtensions[SqlOperationCapability.key];
      if (!_enabled() || !SqlOperationCapability.supported(capability)) {
        return _error(request, 'CAPABILITY_UNAVAILABLE');
      }
      final token = context.clientToken;
      if (token == null || token.trim().isEmpty) return _error(request, 'SQL_OPERATION_AUTHORIZATION_DENIED');
      const reader = SqlOperationParamsReader();
      final params = request.params;
      if (params is Map<String, dynamic> &&
          ['client_token', 'clientToken', 'auth'].any((k) => params[k] != null && params[k] != token)) {
        return _error(request, 'SQL_OPERATION_AUTHORIZATION_DENIED');
      }
      if (method == 'sql.operation.execute' && params is Map<String, dynamic>) {
        final limits = capability! as Map;
        if (params['steps'] is List && (params['steps'] as List).length > (limits['maxSteps'] as int) ||
            params['maxAffectedRows'] is int &&
                (params['maxAffectedRows'] as int) > (limits['maxAffectedRows'] as int) ||
            params['timeoutMs'] is int && (params['timeoutMs'] as int) > (limits['timeoutMs'] as int)) {
          return _error(request, 'SQL_OPERATION_NEGOTIATED_LIMIT');
        }
      }
      final result = switch (method) {
        'sql.operation.execute' => await _executor.execute(reader.plan(request.params), token, context.agentId),
        'sql.operation.get' => await _executor.get(reader.reference(request.params), token, context.agentId),
        'sql.operation.cancel' => await _executor.cancel(reader.reference(request.params), token, context.agentId),
        _ => Failure<SqlOperationJournalEntry, Exception>(
          SqlOperationFailure(code: 'SQL_OPERATION_METHOD_UNKNOWN', message: 'Unknown operation method.'),
        ),
      };
      return await result.fold(
        (entry) => RpcResponse.success(
          id: request.id,
          result: {
            'operationId': entry.operationId,
            'fingerprint': entry.fingerprint,
            'executionId': entry.executionId,
            'state': switch (entry.state) {
              SqlOperationJournalState.executing => 'executando',
              SqlOperationJournalState.completed => 'concluida',
              SqlOperationJournalState.rolledBack => 'rollback_confirmado',
              SqlOperationJournalState.outcomeUnknown => 'resultado_desconhecido',
              SqlOperationJournalState.cancellationRequested => 'cancelamento_solicitado',
              SqlOperationJournalState.cancelled => 'cancelada',
            },
            'directlyAffectedRows': entry.directlyAffectedRows,
            'updatedAt': entry.updatedAt.toUtc().toIso8601String(),
            if (![
              SqlOperationJournalState.executing,
              SqlOperationJournalState.cancellationRequested,
            ].contains(entry.state))
              'completedAt': entry.updatedAt.toUtc().toIso8601String(),
          },
        ),
        (error) => _error(request, error is domain.Failure ? error.code : 'SQL_OPERATION_FAILED'),
      );
    } on Object catch (error) {
      return _error(
        request,
        error is domain.Failure ? error.code : 'SQL_OPERATION_FAILED',
        error is SqlOperationFailure ? RpcErrorCode.invalidParams : RpcErrorCode.internalError,
      );
    }
  }

  RpcResponse _error(RpcRequest request, String code, [int rpcCode = -32000]) => RpcResponse.error(
    id: request.id,
    error: RpcError(
      code: rpcCode,
      message: 'SQL operation refused.',
      data: {
        'failure_code': code,
        'retryable': false,
      },
    ),
  );
}
