import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_captured_output_constants.dart';
import 'package:plug_agente/domain/actions/agent_action_captured_output_chunker.dart';

void main() {
  group('AgentActionCapturedOutputChunker', () {
    test('should not spill when utf8 size is within inline max', () {
      final text = 'a' * (AgentActionCapturedOutputConstants.inlineMaxUtf8Bytes ~/ 2);
      expect(AgentActionCapturedOutputChunker.shouldSpillToChunks(text), isFalse);
    });

    test('should spill and round-trip utf8 text across chunk boundaries', () {
      final text = 'line\n' * 6000;
      expect(AgentActionCapturedOutputChunker.shouldSpillToChunks(text), isTrue);

      final slices = AgentActionCapturedOutputChunker.split(text);
      expect(slices.length, greaterThanOrEqualTo(1));
      if (utf8.encode(text).length > AgentActionCapturedOutputConstants.chunkPayloadUtf8Bytes) {
        expect(slices.length, greaterThan(1));
      }

      final rebuilt = StringBuffer();
      for (final slice in slices) {
        expect(slice.chunkIndex, slices.indexOf(slice));
        rebuilt.write(slice.payload);
      }
      expect(rebuilt.toString(), text);
      expect(utf8.encode(rebuilt.toString()).length, utf8.encode(text).length);
    });
  });
}
