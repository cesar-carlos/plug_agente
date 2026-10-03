import 'dart:async';
import 'dart:collection';

/// Serializes effects within one control-event family without blocking RPCs.
final class TransportControlDecodeSequence {
  TransportControlDecodeSequence({
    required this.decode,
    required this.decodeAsync,
    required this.needsAsync,
    required this.apply,
    required this.onError,
    required this.sessionGeneration,
    required this.isConnected,
  });

  final dynamic Function(dynamic) decode;
  final Future<dynamic> Function(dynamic) decodeAsync;
  final bool Function(dynamic) needsAsync;
  final void Function(dynamic) apply;
  final void Function(Object, StackTrace) onError;
  final int Function() sessionGeneration;
  final bool Function() isConnected;
  final Queue<({dynamic payload, int session})> _queue = Queue();
  int _epoch = 0;
  bool _running = false;
  int get waiting => _queue.length;
  int asyncDecodes = 0;

  void accept(dynamic payload) {
    if (!isConnected()) return;
    if (!_running && !needsAsync(payload)) {
      try {
        apply(decode(payload));
      } on Object catch (error, stack) {
        onError(error, stack);
      }
      return;
    }
    _queue.add((payload: payload, session: sessionGeneration()));
    if (!_running) {
      _running = true;
      unawaited(_drain(_epoch));
    }
  }

  Future<void> _drain(int epoch) async {
    try {
      while (epoch == _epoch && _queue.isNotEmpty) {
        final work = _queue.removeFirst();
        if (!isConnected() || work.session != sessionGeneration()) continue;
        try {
          dynamic decoded;
          if (needsAsync(work.payload)) {
            asyncDecodes++;
            decoded = await decodeAsync(work.payload);
          } else {
            decoded = decode(work.payload);
          }
          if (epoch == _epoch && isConnected() && work.session == sessionGeneration()) apply(decoded);
        } on Object catch (error, stack) {
          if (epoch == _epoch) onError(error, stack);
        }
      }
    } finally {
      if (epoch == _epoch) _running = false;
    }
  }

  void reset() {
    _epoch++;
    _queue.clear();
    _running = false;
  }
}
