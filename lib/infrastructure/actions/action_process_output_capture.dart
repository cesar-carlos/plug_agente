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
  }) async {
    if (!isEnabled) {
      await stream.drain<void>();
      return AgentActionCapturedOutput.disabled;
    }

    final safeMaxBytes = maxBytes < 0 ? 0 : maxBytes;
    final builder = BytesBuilder(copy: false);
    var collectedBytes = 0;
    var isTruncated = false;

    await for (final chunk in stream) {
      if (collectedBytes < safeMaxBytes) {
        final available = safeMaxBytes - collectedBytes;
        final bytesToTake = chunk.length <= available ? chunk : chunk.take(available).toList(growable: false);
        builder.add(bytesToTake);
      }
      collectedBytes += chunk.length;
      if (collectedBytes > safeMaxBytes) {
        isTruncated = true;
      }
    }

    final decoded = ActionProcessOutputDecoder.decode(
      builder.takeBytes(),
      mode: encoding,
    );
    final text = redactBeforePersisting ? redactor.redactText(decoded) : decoded;
    return AgentActionCapturedOutput(
      text: text,
      isCaptured: true,
      isTruncated: isTruncated,
    );
  }
}
