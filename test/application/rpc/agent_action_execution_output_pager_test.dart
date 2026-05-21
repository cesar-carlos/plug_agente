import 'package:plug_agente/application/rpc/agent_action_execution_output_pager.dart';
import 'package:test/test.dart';

void main() {
  group('sliceUtf8TextWindow', () {
    test('should slice ASCII by UTF-8 byte length', () {
      final window = sliceUtf8TextWindow('abcdefghij', 0, 4);
      expect(window.text, 'abcd');
      expect(window.nextOffset, 4);
      expect(window.totalBytes, 10);
      expect(window.responseTruncated, isTrue);
      expect(window.effectiveStart, 0);
    });

    test('should return empty tail when offset equals UTF-8 length', () {
      final window = sliceUtf8TextWindow('ab', 2, 10);
      expect(window.text, '');
      expect(window.nextOffset, 2);
      expect(window.responseTruncated, isFalse);
    });
  });

  group('buildCapturedOutputRpcMap', () {
    test('should report no capture when stream was not captured', () {
      final map = buildCapturedOutputRpcMap(
        captured: false,
        storageTruncated: false,
        fullText: null,
        offsetUtf8: 0,
        maxBytes: 10,
      );
      expect(map['captured'], isFalse);
      expect(map['utf8_total_bytes'], 0);
      expect(map.containsKey('text'), isFalse);
    });
  });
}
