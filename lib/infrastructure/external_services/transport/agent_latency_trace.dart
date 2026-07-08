/// Wall-clock phase timings for a single inbound RPC when the consumer opted in
/// via `meta.requestServerTimings` and `agentPhaseTimings` is negotiated.
final class AgentLatencyTrace {
  AgentLatencyTrace({DateTime Function()? nowProvider}) : _nowProvider = nowProvider ?? DateTime.now;

  final DateTime Function() _nowProvider;
  final Map<String, double> _phasesMs = <String, double>{};
  DateTime? _dispatchStartedAt;

  void markFrameDecodeComplete() {
    _recordPhase('frame_decode_ms', _elapsedSinceStart());
  }

  void markPreDispatchComplete() {
    _recordPhase('schema_validate_ms', _elapsedSinceStart());
  }

  void markDispatchStarted() {
    _dispatchStartedAt = _nowProvider();
  }

  void markDispatchComplete({required bool isSqlMethod}) {
    final dispatchStartedAt = _dispatchStartedAt;
    if (dispatchStartedAt == null) {
      return;
    }
    final dispatchMs = _nowProvider().difference(dispatchStartedAt).inMicroseconds / 1000.0;
    if (isSqlMethod) {
      _recordPhase('sql_execute_ms', dispatchMs);
    } else {
      _recordPhase('dispatch_ms', dispatchMs);
    }
  }

  Map<String, double>? toAgentPhases() {
    if (_phasesMs.isEmpty) {
      return null;
    }
    return Map<String, double>.unmodifiable(_phasesMs);
  }

  DateTime? _startedAt;

  double _elapsedSinceStart() {
    _startedAt ??= _nowProvider();
    return _nowProvider().difference(_startedAt!).inMicroseconds / 1000.0;
  }

  void _recordPhase(String key, double valueMs) {
    if (valueMs < 0) {
      return;
    }
    _phasesMs[key] = valueMs;
  }
}
