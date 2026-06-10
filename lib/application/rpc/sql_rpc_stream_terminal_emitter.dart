import 'dart:developer' as developer;

import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';

class SqlRpcStreamTerminalEmitter {
  const SqlRpcStreamTerminalEmitter({
    IRpcDispatchMetricsCollector? dispatchMetrics,
  }) : _dispatchMetrics = dispatchMetrics;

  final IRpcDispatchMetricsCollector? _dispatchMetrics;

  /// Emits `rpc:complete` with [status] so the hub can deterministically close
  /// a stream that ended without full success.
  ///
  /// Swallows emit errors and records a failure counter so the caller can
  /// return the RPC error response even when the terminal complete fails.
  Future<void> emitTerminalComplete({
    required IRpcStreamEmitter streamEmitter,
    required String streamId,
    required dynamic requestId,
    required int totalRows,
    required StreamTerminalStatus status,
  }) async {
    try {
      await streamEmitter.emitComplete(
        RpcStreamComplete(
          streamId: streamId,
          requestId: requestId,
          totalRows: totalRows,
          terminalStatus: status,
        ),
      );
      _dispatchMetrics?.recordStreamTerminalCompleteEmitted();
    } on Object catch (error, stackTrace) {
      _dispatchMetrics?.recordStreamTerminalCompleteFailed();
      developer.log(
        'Failed to emit terminal rpc:complete '
        'stream_id=$streamId status=${status.name}',
        name: 'rpc.dispatcher',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
