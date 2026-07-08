import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_agent_params_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_sql_params_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validation_support.dart';
import 'package:result_dart/result_dart.dart';

/// Validates RPC request payloads against the published communication contract.
///
/// The implementation enforces the subset of JSON Schema used by the agent at
/// runtime so the published docs match the actual request gate.
class RpcRequestSchemaValidator {
  const RpcRequestSchemaValidator({
    RpcRequestSchemaSqlParamsValidator? sqlParamsValidator,
    RpcRequestSchemaAgentParamsValidator? agentParamsValidator,
  }) : _sqlParamsValidator = sqlParamsValidator ?? const RpcRequestSchemaSqlParamsValidator(),
       _agentParamsValidator = agentParamsValidator ?? const RpcRequestSchemaAgentParamsValidator();

  final RpcRequestSchemaSqlParamsValidator _sqlParamsValidator;
  final RpcRequestSchemaAgentParamsValidator _agentParamsValidator;

  Result<void> validateSingle(
    Map<String, dynamic> data, {
    TransportLimits limits = const TransportLimits(),
  }) {
    final jsonrpc = data['jsonrpc'];
    if (jsonrpc != '2.0') {
      return RpcRequestSchemaValidationSupport.invalidRequest('Field "jsonrpc" must be exactly "2.0"');
    }

    final method = data['method'];
    if (method == null) {
      return RpcRequestSchemaValidationSupport.invalidRequest('Field "method" is required');
    }
    if (method is! String || method.trim().isEmpty) {
      return RpcRequestSchemaValidationSupport.invalidRequest('Field "method" must be a non-empty string');
    }

    final id = data['id'];
    if (id != null && id is! String && id is! num) {
      return RpcRequestSchemaValidationSupport.invalidRequest('Field "id" must be string, number, or null');
    }

    final apiVersion = data['api_version'];
    if (apiVersion != null && apiVersion is! String) {
      return RpcRequestSchemaValidationSupport.invalidRequest('Field "api_version" must be a string');
    }

    final meta = data['meta'];
    if (meta != null) {
      if (meta is! Map<String, dynamic>) {
        return RpcRequestSchemaValidationSupport.invalidRequest('Field "meta" must be an object');
      }
      final metaValidation = RpcRequestSchemaValidationSupport.validateMeta(meta);
      if (metaValidation.isError()) {
        return metaValidation;
      }
    }

    return switch (method) {
      'sql.execute' => _sqlParamsValidator.validateSqlExecuteParams(
        data['params'],
        limits.maxRows,
      ),
      'sql.executeBatch' => _sqlParamsValidator.validateSqlExecuteBatchParams(
        data['params'],
        limits.maxBatchSize,
        limits.maxRows,
      ),
      'sql.bulkInsert' => _sqlParamsValidator.validateSqlBulkInsertParams(
        data['params'],
        limits.maxRows,
      ),
      'sql.cancel' => _sqlParamsValidator.validateSqlCancelParams(data['params']),
      'agent.getProfile' => _agentParamsValidator.validateAgentGetProfileParams(data['params']),
      'agent.getHealth' => _agentParamsValidator.validateOptionalClientTokenAliasParams(
        data['params'],
        'agent.getHealth',
      ),
      AgentActionRpcConstants.agentActionGetExecutionRpcMethodName =>
        _agentParamsValidator.validateAgentActionGetExecutionParams(data['params']),
      AgentActionRpcConstants.agentActionRunRpcMethodName => _agentParamsValidator.validateAgentActionRunParams(
        data['params'],
      ),
      AgentActionRpcConstants.agentActionValidateRunRpcMethodName =>
        _agentParamsValidator.validateAgentActionValidateRunParams(data['params']),
      AgentActionRpcConstants.agentActionCancelRpcMethodName => _agentParamsValidator.validateAgentActionCancelParams(
        data['params'],
      ),
      'client_token.getPolicy' => _agentParamsValidator.validateOptionalClientTokenAliasParams(
        data['params'],
        'client_token.getPolicy',
      ),
      _ => const Success(unit),
    };
  }

  Result<void> validateBatch(
    List<dynamic> data, {
    TransportLimits limits = const TransportLimits(),
  }) {
    if (data.isEmpty) {
      return RpcRequestSchemaValidationSupport.invalidRequest('Batch request cannot be empty');
    }
    if (data.length > limits.maxBatchSize) {
      return RpcRequestSchemaValidationSupport.invalidRequest(
        'Batch request exceeds limit: ${data.length} > ${limits.maxBatchSize}',
      );
    }

    for (var i = 0; i < data.length; i++) {
      final item = data[i];
      if (item is! Map<String, dynamic>) {
        return RpcRequestSchemaValidationSupport.invalidRequest(
          'Batch item at index $i must be an object, '
          'got ${item.runtimeType}',
        );
      }
      final result = validateSingle(item, limits: limits);
      if (result.isError()) {
        final failure = result.exceptionOrNull()! as domain.Failure;
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Batch item at index $i: ${failure.message}',
            context: failure.context,
          ),
        );
      }
    }
    return const Success(unit);
  }
}
