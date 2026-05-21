import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_process_output_decoder.dart';

void main() {
  group('ActionProcessOutputDecoder', () {
    test('should return empty string for empty bytes', () {
      expect(ActionProcessOutputDecoder.decode(const <int>[]), '');
    });

    test('should decode bytes as utf8 when policy requests utf8', () {
      final bytes = utf8.encode('acao');
      expect(
        ActionProcessOutputDecoder.decode(bytes, mode: AgentActionOutputEncodingMode.utf8),
        'acao',
      );
    });

    test('should decode bytes using host encoding on Windows for systemConsole', () {
      if (!Platform.isWindows) {
        return;
      }

      final bytes = systemEncoding.encode('acao');
      expect(ActionProcessOutputDecoder.decode(bytes), 'acao');
    });
  });
}
