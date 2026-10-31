import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

/// Method-to-schema lookup for JSON-RPC payloads whose shape depends on the
/// published RPC method name.
class RpcMethodSchemaCatalog {
  const RpcMethodSchemaCatalog();

  static const Map<String, String> _paramsSchemaByMethod = <String, String>{
    'agent.action.sendInput': TransportSchemaIds.paramsAgentActionSendInput,
    'agent.action.closeInput': TransportSchemaIds.paramsAgentActionCloseInput,
    'agent.action.getInputStatus': TransportSchemaIds.paramsAgentActionGetInputStatus,
    'agent.action.readIo': TransportSchemaIds.paramsAgentActionReadIo,
    'agent.action.listAvailable': TransportSchemaIds.paramsAgentActionListAvailable,
    'agent.action.findExecution': TransportSchemaIds.paramsAgentActionFindExecution,
    'sql.describeSchema': TransportSchemaIds.paramsSourceSchema,
    'sql.describeSource': TransportSchemaIds.paramsSourceDiscovery,
    'sql.operation.execute': TransportSchemaIds.paramsSqlOperationExecute,
    'sql.operation.get': TransportSchemaIds.paramsSqlOperationReference,
    'sql.operation.cancel': TransportSchemaIds.paramsSqlOperationReference,
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
    'agent.action.sendInput': TransportSchemaIds.resultAgentActionSendInput,
    'agent.action.closeInput': TransportSchemaIds.resultAgentActionCloseInput,
    'agent.action.getInputStatus': TransportSchemaIds.resultAgentActionGetInputStatus,
    'agent.action.readIo': TransportSchemaIds.resultAgentActionReadIo,
    'agent.action.listAvailable': TransportSchemaIds.resultAgentActionListAvailable,
    'agent.action.findExecution': TransportSchemaIds.resultAgentActionFindExecution,
    'sql.describeSchema': TransportSchemaIds.resultSourceSchema,
    'sql.describeSource': TransportSchemaIds.resultSourceDiscovery,
    'sql.operation.execute': TransportSchemaIds.resultSqlOperation,
    'sql.operation.get': TransportSchemaIds.resultSqlOperation,
    'sql.operation.cancel': TransportSchemaIds.resultSqlOperation,
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
