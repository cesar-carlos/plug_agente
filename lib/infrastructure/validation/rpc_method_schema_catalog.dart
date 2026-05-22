import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

/// Method-to-schema lookup for JSON-RPC payloads whose shape depends on the
/// published RPC method name.
class RpcMethodSchemaCatalog {
  const RpcMethodSchemaCatalog();

  static const Map<String, String> _paramsSchemaByMethod = <String, String>{
    'sql.execute': TransportSchemaIds.paramsSqlExecute,
    'sql.executeBatch': TransportSchemaIds.paramsSqlExecuteBatch,
    'sql.bulkInsert': TransportSchemaIds.paramsSqlBulkInsert,
    'sql.cancel': TransportSchemaIds.paramsSqlCancel,
    'agent.getProfile': TransportSchemaIds.paramsAgentGetProfile,
    'agent.getHealth': TransportSchemaIds.paramsAgentGetHealth,
    'client_token.getPolicy': TransportSchemaIds.paramsClientTokenGetPolicy,
    AgentActionRpcConstants.agentActionRunRpcMethodName: TransportSchemaIds.paramsAgentActionRun,
    AgentActionRpcConstants.agentActionValidateRunRpcMethodName: TransportSchemaIds.paramsAgentActionValidateRun,
    AgentActionRpcConstants.agentActionCancelRpcMethodName: TransportSchemaIds.paramsAgentActionCancel,
    AgentActionRpcConstants.agentActionGetExecutionRpcMethodName: TransportSchemaIds.paramsAgentActionGetExecution,
  };

  static const Map<String, String> _resultSchemaByMethod = <String, String>{
    'sql.execute': TransportSchemaIds.resultSqlExecute,
    'sql.executeBatch': TransportSchemaIds.resultSqlExecuteBatch,
    'sql.bulkInsert': TransportSchemaIds.resultSqlBulkInsert,
    'sql.cancel': TransportSchemaIds.resultSqlCancel,
    'agent.getProfile': TransportSchemaIds.resultAgentGetProfile,
    'agent.getHealth': TransportSchemaIds.resultAgentGetHealth,
    'client_token.getPolicy': TransportSchemaIds.resultClientTokenGetPolicy,
    AgentActionRpcConstants.agentActionRunRpcMethodName: TransportSchemaIds.resultAgentActionGetExecution,
    AgentActionRpcConstants.agentActionValidateRunRpcMethodName: TransportSchemaIds.resultAgentActionValidateRun,
    AgentActionRpcConstants.agentActionCancelRpcMethodName: TransportSchemaIds.resultAgentActionCancel,
    AgentActionRpcConstants.agentActionGetExecutionRpcMethodName: TransportSchemaIds.resultAgentActionGetExecution,
  };

  String? paramsSchemaFor(String method) => _paramsSchemaByMethod[method];

  String? resultSchemaFor(String method) => _resultSchemaByMethod[method];

  Map<String, String> get paramsSchemaByMethod => _paramsSchemaByMethod;

  Map<String, String> get resultSchemaByMethod => _resultSchemaByMethod;
}
