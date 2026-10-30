import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/log_sanitizer.dart';

void main() {
  group('LogSanitizer', () {
    test('redacts I/O frames and credentials inside nested lists', () {
      final frame = <String, dynamic>{
        'enc': 'json',
        'cmp': 'none',
        'payload': [0, 255, 26],
        'requestId': 'nested-request',
        'client_token': 'private-credential',
        'data_base64': 'AP8a',
      };
      final input = [
        [frame],
      ];
      final output = LogSanitizer.sanitize(input) as List;
      final sanitized = (output.single as List).single as Map;
      expect(sanitized['payload'], '[REDACTED]');
      expect(sanitized['client_token'], '[REDACTED]');
      expect(sanitized['data_base64'], '[REDACTED]');
      expect(sanitized['requestId'], 'nested-request');
      expect(frame['payload'], [0, 255, 26]);
      frame['requestId'] = 'changed';
      expect(sanitized['requestId'], 'nested-request');
    });

    test('bounds cyclic nested lists without retaining the source collection', () {
      final cyclic = <dynamic>[];
      cyclic.add(cyclic);
      final output = LogSanitizer.sanitize(cyclic);
      expect('$output', contains('MAX_DEPTH'));
    });

    test('redacts opaque frame bodies and faithful I/O bytes without mutating transport data', () {
      final frame = <String, dynamic>{
        'schemaVersion': '1.0',
        'enc': 'json',
        'cmp': 'none',
        'requestId': 'request',
        'payload': [112, 114, 105, 118, 97, 116, 101],
      };
      final input = <String, dynamic>{
        'frame': frame,
        'io': {'initial_input_base64': 'cHJpdmF0ZQ=='},
        'events': [
          {'stream': 'stdout', 'data_base64': 'cHJpdmF0ZQ==', 'sequence': 1},
        ],
      };
      final out = LogSanitizer.sanitizeMap(input);
      expect((out['frame'] as Map)['payload'], '[REDACTED]');
      expect((out['frame'] as Map)['requestId'], 'request');
      expect((out['io'] as Map)['initial_input_base64'], '[REDACTED]');
      expect(((out['events'] as List).single as Map)['data_base64'], '[REDACTED]');
      expect(((out['events'] as List).single as Map)['sequence'], 1);
      expect(frame['payload'], [112, 114, 105, 118, 97, 116, 101]);
      expect((input['io'] as Map)['initial_input_base64'], 'cHJpdmF0ZQ==');
    });
    test('should redact client_token in nested params map', () {
      final map = <String, dynamic>{
        'jsonrpc': '2.0',
        'params': <String, dynamic>{
          'sql': 'SELECT 1',
          'client_token': 'secret-token-value',
        },
      };

      final out = LogSanitizer.sanitizeMap(map);
      final params = out['params']! as Map<String, dynamic>;

      expect(params['client_token'], '[REDACTED]');
      expect(params['sql'], 'SELECT 1');
    });

    test('should not redact keys that only contain password as substring', () {
      final map = <String, dynamic>{
        'notpassword': 'visible',
        'safe_field': 'ok',
      };
      final out = LogSanitizer.sanitizeMap(map);
      expect(out['notpassword'], 'visible');
      expect(out['safe_field'], 'ok');
    });

    test('should redact keys ending with _token', () {
      final map = <String, dynamic>{'oauth_token': 'x'};
      final out = LogSanitizer.sanitizeMap(map);
      expect(out['oauth_token'], '[REDACTED]');
    });

    test('should truncate very deep maps', () {
      var deep = <String, dynamic>{'k': 'v'};
      for (var i = 0; i < 30; i++) {
        deep = <String, dynamic>{'n': deep};
      }
      final out = LogSanitizer.sanitizeMap(deep);
      expect('$out', contains('MAX_DEPTH'));
    });

    test('should truncate long lists in sanitize', () {
      final list = List<int>.generate(250, (i) => i);
      final out = LogSanitizer.sanitize(list);
      expect(out, isA<List<dynamic>>());
      final asList = out as List<dynamic>;
      expect(asList.length, greaterThan(200));
      expect(asList.last.toString(), contains('LIST_TRUNCATED'));
    });
  });
}
