import 'dart:math' as math;

import 'package:plug_agente/core/constants/connection_constants.dart';

/// Stable `error.data.reason` values and related technical message prefixes for
/// strict JSON-RPC batch validation.
abstract final class RpcBatchConstants {
  static const String duplicateRequestIdsReason = 'batch_duplicate_ids';

  static const String exceedsLimitReason = 'batch_exceeds_limit';

  static const String duplicateRequestIdsTechnicalMessagePrefix = 'Batch contains duplicate request IDs: ';

  static const String exceedsLimitTechnicalMessagePrefix = 'Batch exceeds limit: ';

  /// Maximum concurrent JSON-RPC batch item dispatches in Phase 1 parallel MVP.
  static const int maxParallelJsonRpcBatchDispatchConcurrency = 4;

  /// Read-only RPC methods eligible for homogeneous parallel JSON-RPC batch dispatch.
  static const List<String> parallelJsonRpcBatchDispatchAllowedMethodsOrdered = <String>[
    'agent.getHealth',
    'agent.getProfile',
    'client_token.getPolicy',
    'agent.action.getExecution',
    'agent.action.validateRun',
    'rpc.discover',
  ];

  static final Set<String> parallelJsonRpcBatchDispatchAllowedMethods = Set<String>.from(
    parallelJsonRpcBatchDispatchAllowedMethodsOrdered,
  );

  /// RPC method handled by Phase 2 parallel dispatch when every item is SELECT-only.
  static const String parallelJsonRpcBatchSqlExecuteMethod = 'sql.execute';

  /// Pool-aware concurrency cap for homogeneous SELECT-only `sql.execute` batches.
  static int parallelJsonRpcBatchSqlExecuteConcurrencyForPoolSize(int poolSize) {
    return math.min(
      ConnectionConstants.readOnlyBatchParallelismForPoolSize(poolSize),
      maxParallelJsonRpcBatchDispatchConcurrency,
    );
  }
}
