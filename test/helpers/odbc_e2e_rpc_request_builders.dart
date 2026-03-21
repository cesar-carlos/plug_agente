import 'package:plug_agente/domain/protocol/protocol.dart';

RpcRequest e2eRpcExecute({
  required String id,
  required String sql,
  Map<String, dynamic>? options,
}) {
  return RpcRequest(
    jsonrpc: '2.0',
    method: 'sql.execute',
    id: id,
    params: <String, dynamic>{
      'sql': sql,
      if (options != null && options.isNotEmpty) 'options': options,
    },
  );
}

/// `sql.execute` with top-level `params` (see `rpc.params.sql-execute.schema.json`).
RpcRequest e2eRpcExecuteWithParams({
  required String id,
  required String sql,
  required Map<String, dynamic> boundParams,
  Map<String, dynamic>? options,
}) {
  return RpcRequest(
    jsonrpc: '2.0',
    method: 'sql.execute',
    id: id,
    params: <String, dynamic>{
      'sql': sql,
      'params': boundParams,
      if (options != null && options.isNotEmpty) 'options': options,
    },
  );
}

RpcRequest e2eRpcExecuteBatch({
  required String id,
  required List<Map<String, dynamic>> commands,
  Map<String, dynamic>? options,
}) {
  return RpcRequest(
    jsonrpc: '2.0',
    method: 'sql.executeBatch',
    id: id,
    params: <String, dynamic>{
      'commands': commands,
      'options': options ?? <String, dynamic>{},
    },
  );
}

RpcRequest e2eRpcCancel({
  required String id,
  String? executionId,
  String? requestId,
}) {
  assert(
    (executionId != null && executionId.isNotEmpty) ||
        (requestId != null && requestId.isNotEmpty),
    'executionId or requestId required',
  );
  return RpcRequest(
    jsonrpc: '2.0',
    method: 'sql.cancel',
    id: id,
    params: <String, dynamic>{
      if (executionId != null && executionId.isNotEmpty)
        'execution_id': executionId,
      if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
    },
  );
}
