import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/log_sanitizer.dart';

void main() {
  group('LogSanitizer', () {
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
