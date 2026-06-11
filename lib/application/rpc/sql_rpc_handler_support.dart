import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:result_dart/result_dart.dart';

typedef SqlRpcInvalidParams =
    RpcResponse Function(
      RpcRequest request,
      String detail, {
      String? rpcReason,
      Map<String, dynamic> extraFields,
    });

typedef SqlRpcConsumeIdempotentCache =
    Future<RpcResponse?> Function(
      RpcRequest request,
      String? idempotencyKey,
      String idempotencyFingerprint,
    );

typedef SqlRpcStoreIdempotentSuccess =
    Future<void> Function({
      required RpcRequest request,
      required String? idempotencyKey,
      required String idempotencyFingerprint,
      required RpcResponse response,
    });

typedef SqlRpcRunIdempotentExecution =
    Future<RpcResponse> Function({
      required RpcRequest request,
      required String? idempotencyKey,
      required String idempotencyFingerprint,
      required Future<RpcResponse> Function() execute,
      bool idempotentCachePrefetched,
    });

typedef SqlRpcAuthorizeWithBudget =
    Future<Result<void>> Function({
      required String token,
      required String sql,
      required String? requestDatabase,
      required String? requestId,
      required String method,
      required DateTime? deadline,
    });

typedef SqlRpcEffectiveStageTimeout =
    Duration? Function({
      required DateTime? deadline,
      required Duration stageBudget,
    });

class SqlRpcMethodHandlerSupport {
  const SqlRpcMethodHandlerSupport({
    required this.invalidParams,
    required this.methodNotFound,
    required this.executionNotFound,
    required this.consumeIdempotentCacheIfAny,
    required this.storeIdempotentSuccessIfApplicable,
    required this.runIdempotentExecution,
    required this.buildMissingClientTokenFailure,
    required this.authorizeWithBudget,
    required this.effectiveStageTimeout,
  });

  final SqlRpcInvalidParams invalidParams;
  final RpcResponse Function(RpcRequest request) methodNotFound;
  final RpcResponse Function(RpcRequest request) executionNotFound;
  final SqlRpcConsumeIdempotentCache consumeIdempotentCacheIfAny;
  final SqlRpcStoreIdempotentSuccess storeIdempotentSuccessIfApplicable;
  final SqlRpcRunIdempotentExecution runIdempotentExecution;
  final domain.ConfigurationFailure Function() buildMissingClientTokenFailure;
  final SqlRpcAuthorizeWithBudget authorizeWithBudget;
  final SqlRpcEffectiveStageTimeout effectiveStageTimeout;
}
