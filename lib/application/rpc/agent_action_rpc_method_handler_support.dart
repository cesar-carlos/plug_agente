import 'package:plug_agente/domain/protocol/protocol.dart';

typedef AgentActionRpcInvalidParams =
    RpcResponse Function(
      RpcRequest request,
      String detail, {
      String? rpcReason,
      Map<String, dynamic> extraFields,
    });

typedef AgentActionRpcInternalError =
    RpcResponse Function(
      RpcRequest request,
      String detail,
    );

typedef AgentActionRpcConsumeIdempotentCache =
    Future<RpcResponse?> Function(
      RpcRequest request,
      String? idempotencyKey,
      String idempotencyFingerprint,
    );

typedef AgentActionRpcStoreIdempotentSuccess =
    Future<void> Function({
      required RpcRequest request,
      required String? idempotencyKey,
      required String idempotencyFingerprint,
      required RpcResponse response,
    });

typedef AgentActionRpcRunIdempotentExecution =
    Future<RpcResponse> Function({
      required RpcRequest request,
      required String? idempotencyKey,
      required String idempotencyFingerprint,
      required Future<RpcResponse> Function() execute,
      bool idempotentCachePrefetched,
    });

class AgentActionRpcMethodHandlerSupport {
  const AgentActionRpcMethodHandlerSupport({
    required this.invalidParams,
    required this.internalError,
    required this.consumeIdempotentCacheIfAny,
    required this.storeIdempotentSuccessIfApplicable,
    required this.runIdempotentExecution,
  });

  final AgentActionRpcInvalidParams invalidParams;
  final AgentActionRpcInternalError internalError;
  final AgentActionRpcConsumeIdempotentCache consumeIdempotentCacheIfAny;
  final AgentActionRpcStoreIdempotentSuccess storeIdempotentSuccessIfApplicable;
  final AgentActionRpcRunIdempotentExecution runIdempotentExecution;
}
