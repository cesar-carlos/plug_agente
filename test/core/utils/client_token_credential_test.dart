import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';

void main() {
  group('normalizeClientCredentialToken', () {
    test('should trim and strip Bearer prefix', () {
      expect(
        normalizeClientCredentialToken('  Bearer abc  '),
        'abc',
      );
    });

    test('should be case-insensitive on Bearer', () {
      expect(normalizeClientCredentialToken('bearer x'), 'x');
    });
  });

  group('hashClientCredentialToken', () {
    test('should match hash of normalized credential', () {
      final a = hashClientCredentialToken('Bearer secret');
      final b = hashClientCredentialToken('secret');
      expect(a, b);
    });
  });
}
