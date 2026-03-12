import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';

void main() {
  group('JwtJwksVerifier', () {
    test('should return failure when config is null', () async {
      final verifier = JwtJwksVerifier(() async => null);

      final result = await verifier.verify('any-token');

      expect(result.isError(), isTrue);
    });

    test('should return failure when jwksUrl is empty', () async {
      final verifier = JwtJwksVerifier(
        () async => const JwksConfig(jwksUrl: ''),
      );

      final result = await verifier.verify('any-token');

      expect(result.isError(), isTrue);
    });

    test('should return failure for empty token', () async {
      final verifier = JwtJwksVerifier(
        () async => const JwksConfig(jwksUrl: 'https://example.com/jwks.json'),
      );

      final result = await verifier.verify('');

      expect(result.isError(), isTrue);
    });

    test('should reject alg none before verification', () async {
      final token = _buildTokenWithAlg('none');
      final verifier = JwtJwksVerifier(
        () async => const JwksConfig(jwksUrl: 'https://example.com/jwks.json'),
      );

      final result = await verifier.verify(token);

      expect(result.isError(), isTrue);
    });
  });
}

String _buildTokenWithAlg(String alg) {
  final header = '{"alg":"$alg","typ":"JWT"}';
  const payload = '{"policy":{"client_id":"c1","all_tables":true}}';
  return '${_b64(header)}.${_b64(payload)}.sig';
}

String _b64(String s) {
  final bytes = s.codeUnits;
  return base64Url.encode(bytes);
}
