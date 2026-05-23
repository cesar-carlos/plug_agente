import 'package:plug_agente/core/constants/rpc_batch_constants.dart';

/// Parsed `parallelBatchDispatch` extension negotiated with the hub.
class ParallelBatchDispatchNegotiation {
  const ParallelBatchDispatchNegotiation({
    required this.enabled,
    required this.maxConcurrency,
    required this.mixedReadOnlyMethods,
    required this.selectOnlySqlExecute,
  });

  final bool enabled;
  final int maxConcurrency;
  final bool mixedReadOnlyMethods;
  final bool selectOnlySqlExecute;

  static ParallelBatchDispatchNegotiation? fromNegotiatedExtensions(
    Map<String, dynamic> negotiatedExtensions,
  ) {
    final raw = negotiatedExtensions['parallelBatchDispatch'];
    if (raw == true) {
      return const ParallelBatchDispatchNegotiation(
        enabled: true,
        maxConcurrency: RpcBatchConstants.maxParallelJsonRpcBatchDispatchConcurrency,
        mixedReadOnlyMethods: true,
        selectOnlySqlExecute: true,
      );
    }
    if (raw is! Map<String, dynamic>) {
      return null;
    }
    final enabled = raw['enabled'] as bool? ?? false;
    if (!enabled) {
      return null;
    }
    final maxConcurrency = raw['maxConcurrency'];
    return ParallelBatchDispatchNegotiation(
      enabled: true,
      maxConcurrency: maxConcurrency is int && maxConcurrency > 0
          ? maxConcurrency
          : RpcBatchConstants.maxParallelJsonRpcBatchDispatchConcurrency,
      mixedReadOnlyMethods: raw['mixedReadOnlyMethods'] as bool? ?? false,
      selectOnlySqlExecute: raw['selectOnlySqlExecute'] as bool? ?? false,
    );
  }

  static Map<String, dynamic> agentAdvertisement({
    required bool enabled,
    int maxConcurrency = RpcBatchConstants.maxParallelJsonRpcBatchDispatchConcurrency,
    bool mixedReadOnlyMethods = true,
    bool selectOnlySqlExecute = true,
  }) {
    return <String, dynamic>{
      'enabled': enabled,
      'maxConcurrency': maxConcurrency,
      'mixedReadOnlyMethods': mixedReadOnlyMethods,
      'selectOnlySqlExecute': selectOnlySqlExecute,
    };
  }
}
