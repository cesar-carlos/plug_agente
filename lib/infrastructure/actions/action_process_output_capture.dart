import 'dart:async';
import 'dart:typed_data';

import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_process_output_decoder.dart';

abstract final class ActionProcessOutputCapture {
  static Future<AgentActionCapturedOutput> capture(
    Stream<List<int>> stream, {
    required bool isEnabled,
    required int maxBytes,
    required AgentActionOutputEncodingMode encoding,
    required AgentActionRedactor redactor,
    required bool redactBeforePersisting,
  }) => ActionProcessOutputCaptureSession(
    stream,
    isEnabled: isEnabled,
    maxBytes: maxBytes,
    encoding: encoding,
    redactor: redactor,
    redactBeforePersisting: redactBeforePersisting,
  ).result;
}

/// Owns the subscription and bounded buffer, including after a process timeout.
final class ActionProcessOutputCaptureSession {
  ActionProcessOutputCaptureSession(
    Stream<List<int>> stream, {
    required this.isEnabled,
    required int maxBytes,
    required this.encoding,
    required this.redactor,
    required this.redactBeforePersisting,
  }) : _maxBytes = maxBytes < 0 ? 0 : maxBytes {
    _subscription = stream.listen(_add, onError: _onError, onDone: _finish, cancelOnError: true);
    // Observe early pipe failures while the lifecycle is still awaiting exit.
    unawaited(_completion.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  final bool isEnabled;
  final int _maxBytes;
  final AgentActionOutputEncodingMode encoding;
  final AgentActionRedactor redactor;
  final bool redactBeforePersisting;
  // Own the accepted prefix: stream chunks may be views of larger or reused buffers.
  final _builder = BytesBuilder();
  final _completion = Completer<AgentActionCapturedOutput>();
  late final StreamSubscription<List<int>> _subscription;
  Future<AgentActionCapturedOutput>? _cancellation;
  bool _truncated = false;

  Future<AgentActionCapturedOutput> get result => _completion.future;

  void _add(List<int> chunk) {
    if (!isEnabled || _completion.isCompleted) return;
    final available = _maxBytes - _builder.length;
    if (chunk.length > available) _truncated = true;
    if (available > 0) {
      _builder.add(chunk.length <= available ? chunk : chunk.take(available).toList(growable: false));
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    _builder.clear();
    if (!_completion.isCompleted) _completion.completeError(error, stackTrace);
  }

  void _finish() {
    if (_completion.isCompleted) return;
    if (!isEnabled) {
      _completion.complete(AgentActionCapturedOutput.disabled);
      return;
    }
    try {
      List<int> bytes = _builder.takeBytes();
      if (encoding == AgentActionOutputEncodingMode.utf8) {
        bytes = ActionProcessOutputDecoder.clipIncompleteTrailingUtf8(bytes);
      }
      final decoded = ActionProcessOutputDecoder.decode(bytes, mode: encoding);
      _completion.complete(
        AgentActionCapturedOutput(
          text: redactBeforePersisting ? redactor.redactText(decoded) : decoded,
          isCaptured: true,
          isTruncated: _truncated,
        ),
      );
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  Future<AgentActionCapturedOutput> cancel() => _cancellation ??= _cancel();

  Future<AgentActionCapturedOutput> _cancel() async {
    if (!_completion.isCompleted) _truncated = true;
    try {
      await _subscription.cancel();
      _finish();
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
    return result;
  }
}
