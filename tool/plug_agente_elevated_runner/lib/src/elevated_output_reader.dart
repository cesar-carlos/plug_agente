import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Always drains pipes, but retains bytes only when capture was approved.
class ElevatedOutputReader {
  ElevatedOutputReader(
    Stream<List<int>> stream, {
    required this.enabled,
    required this.maxBytes,
  }) {
    _subscription = stream.listen(
      _append,
      onDone: _done.complete,
      onError: (Object error, StackTrace stack) {
        if (!_done.isCompleted) _done.completeError(error, stack);
      },
      cancelOnError: true,
    );
    unawaited(
      _done.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }
  final bool enabled;
  final int maxBytes;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  final Completer<void> _done = Completer<void>();
  late final StreamSubscription<List<int>> _subscription;
  bool _truncated = false;

  void _append(List<int> chunk) {
    if (!enabled) return;
    final remaining = maxBytes - _bytes.length;
    if (chunk.length > remaining) _truncated = true;
    if (remaining > 0)
      _bytes.add(Uint8List.fromList(chunk.take(remaining).toList()));
  }

  Future<({String? text, bool truncated})> finish() async {
    // Descendants may retain inherited pipe handles after the main process exits.
    try {
      await _done.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      _truncated = enabled;
    } finally {
      await _subscription.cancel();
    }
    return (
      text: enabled
          ? utf8.decode(_bytes.takeBytes(), allowMalformed: true)
          : null,
      truncated: _truncated,
    );
  }

  Future<void> dispose() => _subscription.cancel();
}
