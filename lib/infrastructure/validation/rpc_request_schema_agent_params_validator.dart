import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validation_support.dart';
import 'package:result_dart/result_dart.dart';

/// Agent and agent-action RPC parameter validators.
final class RpcRequestSchemaAgentParamsValidator {
  const RpcRequestSchemaAgentParamsValidator();

  Result<void> validateOptionalClientTokenAliasParams(dynamic params, String method) {
    if (params == null) {
      return const Success(unit);
    }
    if (params is! Map<String, dynamic>) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" must be an object when present for method $method',
      );
    }
    const allowedKeys = {'client_token', 'clientToken', 'auth'};
    final extraKeys = params.keys.where(
      (String key) => !allowedKeys.contains(key),
    );
    if (extraKeys.isNotEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }
    return RpcRequestSchemaValidationSupport.validateTokenAliases(params);
  }

  Result<void> validateAgentGetProfileParams(dynamic params) {
    if (params == null) {
      return const Success(unit);
    }
    if (params is! Map<String, dynamic>) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" must be an object when present for method agent.getProfile',
      );
    }
    const allowedKeys = {
      'client_token',
      'clientToken',
      'auth',
      'include_diagnostics',
    };
    final extraKeys = params.keys.where(
      (String key) => !allowedKeys.contains(key),
    );
    if (extraKeys.isNotEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }
    final includeDiagnostics = params['include_diagnostics'];
    if (includeDiagnostics != null && includeDiagnostics is! bool) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params.include_diagnostics" must be a boolean');
    }
    return RpcRequestSchemaValidationSupport.validateTokenAliases(params);
  }

  Result<void> validateAgentActionGetExecutionParams(dynamic params) {
    if (params == null) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" is required for method ${AgentActionRpcConstants.agentActionGetExecutionRpcMethodName}',
      );
    }
    if (params is! Map<String, dynamic>) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" must be an object for method ${AgentActionRpcConstants.agentActionGetExecutionRpcMethodName}',
      );
    }
    const allowedKeys = {
      'execution_id',
      'include_output',
      'stdout_offset',
      'stdout_cursor',
      'output_offset',
      'stderr_offset',
      'stderr_cursor',
      'max_output_bytes',
      AgentActionRpcConstants.agentActionRpcParamTraceId,
      AgentActionRpcConstants.agentActionRpcParamRequestedBy,
      'client_token',
      'clientToken',
      'auth',
    };
    final extraKeys = params.keys.where(
      (String key) => !allowedKeys.contains(key),
    );
    if (extraKeys.isNotEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }
    final executionId = params['execution_id'];
    if (executionId is! String || executionId.trim().isEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params.execution_id" must be a non-empty string',
      );
    }
    final includeOutput = params['include_output'];
    if (includeOutput != null && includeOutput is! bool) {
      return RpcRequestSchemaValidationSupport.invalidParams('Field "params.include_output" must be a boolean');
    }
    for (final key in <String>[
      'stdout_offset',
      'stdout_cursor',
      'output_offset',
      'stderr_offset',
      'stderr_cursor',
    ]) {
      if (!params.containsKey(key)) {
        continue;
      }
      if (RpcRequestSchemaValidationSupport.tryParseNonNegativeInt(params[key]) == null) {
        return RpcRequestSchemaValidationSupport.invalidParams('Field "params.$key" must be a non-negative integer');
      }
    }
    if (params.containsKey('max_output_bytes')) {
      final parsed = RpcRequestSchemaValidationSupport.tryParsePositiveInt(params['max_output_bytes']);
      if (parsed == null) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.max_output_bytes" must be a positive integer',
        );
      }
      if (parsed > AgentActionRpcConstants.maxMaxOutputBytesPerStream) {
        return RpcRequestSchemaValidationSupport.invalidParams(
          'Field "params.max_output_bytes" must be at most '
          '${AgentActionRpcConstants.maxMaxOutputBytesPerStream}',
        );
      }
    }
    final correlationResult = _validateOptionalAgentActionCorrelationParams(params);
    if (correlationResult.isError()) {
      return correlationResult;
    }
    return RpcRequestSchemaValidationSupport.validateTokenAliases(params);
  }

  Result<void> validateAgentActionRunParams(dynamic params) {
    return _validateAgentActionRunOrValidateParams(
      params,
      rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
    );
  }

  Result<void> validateAgentActionValidateRunParams(dynamic params) {
    return _validateAgentActionRunOrValidateParams(
      params,
      rpcMethod: AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
    );
  }

  Result<void> validateAgentActionCancelParams(dynamic params) {
    if (params == null) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" is required for method ${AgentActionRpcConstants.agentActionCancelRpcMethodName}',
      );
    }
    if (params is! Map<String, dynamic>) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" must be an object for method ${AgentActionRpcConstants.agentActionCancelRpcMethodName}',
      );
    }
    const allowedKeys = {
      'execution_id',
      AgentActionRpcConstants.agentActionRpcParamTraceId,
      AgentActionRpcConstants.agentActionRpcParamRequestedBy,
      'client_token',
      'clientToken',
      'auth',
    };
    final extraKeys = params.keys.where(
      (String key) => !allowedKeys.contains(key),
    );
    if (extraKeys.isNotEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }
    final executionId = params['execution_id'];
    if (executionId is! String || executionId.trim().isEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params.execution_id" must be a non-empty string',
      );
    }
    final correlationResult = _validateOptionalAgentActionCorrelationParams(params);
    if (correlationResult.isError()) {
      return correlationResult;
    }
    return RpcRequestSchemaValidationSupport.validateTokenAliases(params);
  }

  Result<void> _validateAgentActionRunOrValidateParams(
    dynamic params, {
    required String rpcMethod,
  }) {
    if (params == null) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" is required for method $rpcMethod',
      );
    }
    if (params is! Map<String, dynamic>) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" must be an object for method $rpcMethod',
      );
    }
    const allowedKeys = {
      'action_id',
      'idempotency_key',
      AgentActionRpcConstants.agentActionRpcParamTriggerId,
      AgentActionRpcConstants.agentActionRpcParamTraceId,
      AgentActionRpcConstants.agentActionRpcParamRequestedBy,
      'client_token',
      'clientToken',
      'auth',
    };
    final extraKeys = params.keys.where((String key) => !allowedKeys.contains(key)).toList();
    if (extraKeys.isNotEmpty) {
      final contextKey = extraKeys.where(AgentActionRpcConstants.remoteContextRpcParamKeys.contains).firstOrNull;
      if (contextKey != null) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Remote agent action RPC does not accept inline context in MVP.',
            code: AgentActionFailureCode.remoteContextNotSupported,
            context: {
              'rpc_error_code': RpcErrorCode.invalidParams,
              'field': contextKey,
              'reason': AgentActionRpcConstants.remoteContextNotSupportedRpcReason,
            },
          ),
        );
      }
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params" contains unsupported properties: '
        '${extraKeys.join(", ")}',
      );
    }
    final actionId = params['action_id'];
    if (actionId is! String || actionId.trim().isEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params.action_id" must be a non-empty string',
      );
    }
    final idempotencyKey = params['idempotency_key'];
    if (idempotencyKey is! String || idempotencyKey.trim().isEmpty) {
      return RpcRequestSchemaValidationSupport.invalidParams(
        'Field "params.idempotency_key" must be a non-empty string',
      );
    }
    final correlationResult = _validateOptionalAgentActionCorrelationParams(params);
    if (correlationResult.isError()) {
      return correlationResult;
    }
    return RpcRequestSchemaValidationSupport.validateTokenAliases(params);
  }

  Result<void> _validateOptionalAgentActionCorrelationParams(Map<String, dynamic> params) {
    for (final key in AgentActionRpcConstants.agentActionRpcCorrelationOnlyParamKeys) {
      final value = params[key];
      if (value != null && (value is! String || value.trim().isEmpty)) {
        return RpcRequestSchemaValidationSupport.invalidParams('Field "params.$key" must be a non-empty string');
      }
    }
    return const Success(unit);
  }
}
