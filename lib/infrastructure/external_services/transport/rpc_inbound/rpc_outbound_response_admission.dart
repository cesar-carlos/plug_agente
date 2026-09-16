import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

/// Bounds responses which have been accepted for dispatch but are still being
/// encoded or emitted to the hub.
///
/// The inbound handler intentionally releases its CPU/ODBC slot before output
/// encoding. Without this second budget, a slow hub can make accepted results
/// accumulate without bound. A reservation belongs to one transport generation;
/// resetting the session invalidates old reservations without decrementing a
/// new session's capacity.
class RpcOutboundResponseAdmission {
  RpcOutboundResponseAdmission({
    int? maxOutstanding,
    MetricsCollector? metricsCollector,
  }) : _maxOutstanding = (maxOutstanding ?? ConnectionConstants.maxConcurrentRpcHandlers).clamp(1, 65536),
       _metricsCollector = metricsCollector;

  final int _maxOutstanding;
  final MetricsCollector? _metricsCollector;
  int _active = 0;
  int _generation = 0;

  int get active => _active;
  int get maxOutstanding => _maxOutstanding;

  RpcOutboundResponseReservation? tryReserve() {
    if (_active >= _maxOutstanding) {
      _metricsCollector?.recordRpcOutboundResponseRejected();
      return null;
    }
    _active++;
    _metricsCollector?.recordRpcOutboundResponseReserved();
    return RpcOutboundResponseReservation._(this, _generation, Stopwatch()..start());
  }

  void reset() {
    _generation++;
    _active = 0;
    _metricsCollector?.recordRpcOutboundResponseReset();
  }

  void _release(int generation, Stopwatch stopwatch) {
    if (generation != _generation) {
      return;
    }
    if (_active > 0) {
      _active--;
    }
    stopwatch.stop();
    _metricsCollector?.recordRpcOutboundResponseReleased(stopwatch.elapsed);
  }
}

class RpcOutboundResponseReservation {
  RpcOutboundResponseReservation._(this._owner, this._generation, this._stopwatch);

  final RpcOutboundResponseAdmission _owner;
  final int _generation;
  final Stopwatch _stopwatch;
  bool _released = false;

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _owner._release(_generation, _stopwatch);
  }
}
