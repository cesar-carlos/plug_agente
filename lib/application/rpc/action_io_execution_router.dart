import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:result_dart/result_dart.dart';

/// Selects by durable ownership, never by caller-supplied capability or scope.
/// Each selected handler remains responsible for its own authorization.
final class ActionIoExecutionRouter implements RpcMethodHandler {
  const ActionIoExecutionRouter({required this.legacy, required this.faithful, required this.ownsExecution});
  final RpcMethodHandler legacy;
  final RpcMethodHandler faithful;
  final Future<Result<bool>> Function(String) ownsExecution;

  @override
  String get method => legacy.method;

  @override
  Future<RpcResponse> handle(RpcRequest request, RpcDispatchContext context) async {
    final params = request.params;
    final id = params is Map<String, dynamic> ? params['execution_id'] : null;
    if (id is! String || id.trim().isEmpty) return legacy.handle(request, context);
    try {
      final owned = (await ownsExecution(id.trim())).getOrThrow();
      return await (owned ? faithful : legacy).handle(request, context);
    } on Object {
      return RpcResponse.error(
        id: request.id,
        error: FailureToRpcErrorMapper.map(
          ActionRuntimeFailure.withContext(
            message: 'Execution ownership could not be verified. Retry the read after storage recovery.',
            code: 'ACTION_IO_STORAGE_UNAVAILABLE',
          ),
          instance: request.id?.toString(),
        ),
      );
    }
  }
}
