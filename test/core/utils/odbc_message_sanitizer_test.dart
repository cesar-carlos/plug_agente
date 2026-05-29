import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/odbc_message_sanitizer.dart';

void main() {
  group('OdbcMessageSanitizer', () {
    test('redacts PWD token embedded in a message', () {
      expect(
        OdbcMessageSanitizer.sanitize('connect failed DRIVER={x};UID=app;PWD=secret;Server=h'),
        'connect failed DRIVER={x};UID=app;PWD=***;Server=h',
      );
    });

    test('redacts PASSWORD token case-insensitively', () {
      expect(
        OdbcMessageSanitizer.sanitize('Password=Hunter2;Database=demo'),
        'Password=***;Database=demo',
      );
    });

    test('leaves messages without credentials untouched', () {
      expect(
        OdbcMessageSanitizer.sanitize("Login failed for user 'sa'."),
        "Login failed for user 'sa'.",
      );
    });

    test('handles empty and null inputs', () {
      expect(OdbcMessageSanitizer.sanitize(''), '');
      expect(OdbcMessageSanitizer.sanitizeNullable(null), isNull);
      expect(OdbcMessageSanitizer.sanitizeNullable('PWD=x'), 'PWD=***');
    });
  });
}
