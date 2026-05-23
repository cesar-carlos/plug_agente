import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler_operations.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

Iterable<RpcMethodHandler> createDefaultRpcMethodHandlers(
  DefaultRpcMethodHandlerOperations operations, {
  Future<Map<String, dynamic>> Function()? loadOpenRpcDocument,
}) {
  return <RpcMethodHandler>[
    if (loadOpenRpcDocument != null) RpcDiscoverRpcHandler(loadDocument: loadOpenRpcDocument),
    SqlExecuteRpcHandler(operations),
    SqlExecuteBatchRpcHandler(operations),
    SqlBulkInsertRpcHandler(operations),
    SqlCancelRpcHandler(operations),
    AgentProfileRpcHandler(operations),
    AgentHealthRpcHandler(operations),
    ClientTokenPolicyRpcHandler(operations),
    AgentActionRunRpcHandler(operations),
    AgentActionValidateRunRpcHandler(operations),
    AgentActionCancelRpcHandler(operations),
    AgentActionGetExecutionRpcHandler(operations),
  ];
}

abstract class _OperationsRpcMethodHandler implements RpcMethodHandler {
  const _OperationsRpcMethodHandler(this.operations);

  final DefaultRpcMethodHandlerOperations operations;
}

class RpcDiscoverRpcHandler implements RpcMethodHandler {
  RpcDiscoverRpcHandler({required Future<Map<String, dynamic>> Function() loadDocument})
    : _loadDocument = loadDocument;

  final Future<Map<String, dynamic>> Function() _loadDocument;

  @override
  String get method => 'rpc.discover';

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) async {
    final document = await _loadDocument();
    return RpcResponse.success(id: request.id, result: document);
  }
}

class SqlExecuteRpcHandler extends _OperationsRpcMethodHandler {
  const SqlExecuteRpcHandler(super.operations);

  @override
  String get method => 'sql.execute';

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) {
    return operations.handleSqlExecute(
      request,
      context.agentId,
      context.clientToken,
      streamEmitter: context.streamEmitter,
      limits: context.limits,
      negotiatedExtensions: context.negotiatedExtensions,
    );
  }
}

class SqlExecuteBatchRpcHandler extends _OperationsRpcMethodHandler {
  const SqlExecuteBatchRpcHandler(super.operations);

  @override
  String get method => 'sql.executeBatch';

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) {
    return operations.handleSqlExecuteBatch(
      request,
      context.agentId,
      context.clientToken,
      limits: context.limits,
      negotiatedExtensions: context.negotiatedExtensions,
    );
  }
}

class SqlBulkInsertRpcHandler extends _OperationsRpcMethodHandler {
  const SqlBulkInsertRpcHandler(super.operations);

  @override
  String get method => 'sql.bulkInsert';

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) {
    return operations.handleSqlBulkInsert(
      request,
      context.clientToken,
      limits: context.limits,
    );
  }
}

class SqlCancelRpcHandler extends _OperationsRpcMethodHandler {
  const SqlCancelRpcHandler(super.operations);

  @override
  String get method => 'sql.cancel';

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) {
    return operations.handleSqlCancel(request);
  }
}

class AgentProfileRpcHandler extends _OperationsRpcMethodHandler {
  const AgentProfileRpcHandler(super.operations);

  @override
  String get method => 'agent.getProfile';

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) {
    return operations.handleAgentGetProfile(
      request,
      context.agentId,
      context.clientToken,
    );
  }
}

class AgentHealthRpcHandler extends _OperationsRpcMethodHandler {
  const AgentHealthRpcHandler(super.operations);

  @override
  String get method => 'agent.getHealth';

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) {
    return operations.handleAgentGetHealth(
      request,
      context.clientToken,
    );
  }
}

class ClientTokenPolicyRpcHandler extends _OperationsRpcMethodHandler {
  const ClientTokenPolicyRpcHandler(super.operations);

  @override
  String get method => 'client_token.getPolicy';

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) {
    return operations.handleClientTokenGetPolicy(
      request,
      context.agentId,
      context.clientToken,
    );
  }
}

class AgentActionRunRpcHandler extends _OperationsRpcMethodHandler {
  const AgentActionRunRpcHandler(super.operations);

  @override
  String get method => AgentActionRpcConstants.agentActionRunRpcMethodName;

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) {
    return operations.handleAgentActionRun(
      request,
      context.agentId,
      context.clientToken,
    );
  }
}

class AgentActionValidateRunRpcHandler extends _OperationsRpcMethodHandler {
  const AgentActionValidateRunRpcHandler(super.operations);

  @override
  String get method => AgentActionRpcConstants.agentActionValidateRunRpcMethodName;

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) {
    return operations.handleAgentActionValidateRun(
      request,
      context.agentId,
      context.clientToken,
    );
  }
}

class AgentActionCancelRpcHandler extends _OperationsRpcMethodHandler {
  const AgentActionCancelRpcHandler(super.operations);

  @override
  String get method => AgentActionRpcConstants.agentActionCancelRpcMethodName;

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) {
    return operations.handleAgentActionCancel(
      request,
      context.agentId,
      context.clientToken,
    );
  }
}

class AgentActionGetExecutionRpcHandler extends _OperationsRpcMethodHandler {
  const AgentActionGetExecutionRpcHandler(super.operations);

  @override
  String get method => AgentActionRpcConstants.agentActionGetExecutionRpcMethodName;

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) {
    return operations.handleAgentActionGetExecution(
      request,
      context.agentId,
      context.clientToken,
    );
  }
}
