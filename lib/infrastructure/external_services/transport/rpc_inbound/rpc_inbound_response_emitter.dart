import 'dart:async';

import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound/rpc_inbound_concurrency_slots.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

/// Emits inbound `rpc:response` frames, releasing deferred slots before emit.
class RpcInboundResponseEmitter {
  RpcInboundResponseEmitter({
    required RpcInboundConcurrencySlots concurrencySlots,
    required Future<void> Function(
      dynamic responseData, {
      Map<Object?, String> methodsById,
    })
    emitRpcResponse,
    MetricsCollector? metricsCollector,
  }) : _concurrencySlots = concurrencySlots,
       _emitRpcResponse = emitRpcResponse,
       _metricsCollector = metricsCollector;

  final RpcInboundConcurrencySlots _concurrencySlots;
  final Future<void> Function(
    dynamic responseData, {
    Map<Object?, String> methodsById,
  })
  _emitRpcResponse;
  final MetricsCollector? _metricsCollector;

  Future<void> emit(
    dynamic responseData, {
    Map<Object?, String> methodsById = const <Object?, String>{},
  }) async {
    _concurrencySlots.releaseDeferredIfPresent();
    // Hub sql.execute must not block the socket handler on outbound encode/emit.
    unawaited(
      _emitRpcResponse(
        responseData,
        methodsById: methodsById,
      ).catchError((Object error, StackTrace stackTrace) {
        _metricsCollector?.recordRpcResponseEmitFailure();
        AppLogger.error(
          'Failed to emit inbound rpc:response',
          error,
          stackTrace,
        );
      }),
    );
  }
}
