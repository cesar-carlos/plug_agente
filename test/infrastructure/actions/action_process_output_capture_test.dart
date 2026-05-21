import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_process_output_capture.dart';

void main() {
  group('ActionProcessOutputCapture', () {
    test('should decode captured bytes using utf8 policy', () async {
      final stream = Stream<List<int>>.value(utf8.encode('acao'));
      final output = await ActionProcessOutputCapture.capture(
        stream,
        isEnabled: true,
        maxBytes: 1024,
        encoding: AgentActionOutputEncodingMode.utf8,
        redactor: const AgentActionRedactor(),
        redactBeforePersisting: true,
      );

      expect(output.isCaptured, isTrue);
      expect(output.text, 'acao');
    });

    test('should skip output redaction when capture policy disables it', () async {
      final stream = Stream<List<int>>.value(utf8.encode('token=abc123'));
      final output = await ActionProcessOutputCapture.capture(
        stream,
        isEnabled: true,
        maxBytes: 1024,
        encoding: AgentActionOutputEncodingMode.utf8,
        redactor: const AgentActionRedactor(),
        redactBeforePersisting: false,
      );

      expect(output.text, 'token=abc123');
    });

    test('should decode captured bytes using system console policy on Windows', () async {
      if (!Platform.isWindows) {
        return;
      }

      final stream = Stream<List<int>>.value(systemEncoding.encode('acao'));
      final output = await ActionProcessOutputCapture.capture(
        stream,
        isEnabled: true,
        maxBytes: 1024,
        encoding: AgentActionOutputEncodingMode.systemConsole,
        redactor: const AgentActionRedactor(),
        redactBeforePersisting: true,
      );

      expect(output.text, 'acao');
    });
  });
}
