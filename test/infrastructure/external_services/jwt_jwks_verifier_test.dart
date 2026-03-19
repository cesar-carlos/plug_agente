import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
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

    test(
      'should open JWKS circuit breaker after consecutive failures',
      () async {
        final now = DateTime.utc(2026, 3, 17, 12);
        final token = _buildTokenWithAlg('none');
        final verifier = JwtJwksVerifier(
          () async => const JwksConfig(jwksUrl: 'https://example.com/jwks.json'),
          failureThreshold: 2,
          now: () => now,
        );

        final first = await verifier.verify(token);
        final second = await verifier.verify(token);
        final third = await verifier.verify(token);

        expect(first.isError(), isTrue);
        expect(second.isError(), isTrue);
        expect(third.isError(), isTrue);
        final failure = third.exceptionOrNull()! as domain.Failure;
        expect(failure.context['reason'], equals('jwks_circuit_open'));
      },
    );

    test(
      'should close JWKS circuit breaker after open duration expires',
      () async {
        var now = DateTime.utc(2026, 3, 17, 12);
        final token = _buildTokenWithAlg('none');
        final verifier = JwtJwksVerifier(
          () async => const JwksConfig(jwksUrl: 'https://example.com/jwks.json'),
          failureThreshold: 1,
          circuitOpenDuration: const Duration(seconds: 10),
          now: () => now,
        );

        final first = await verifier.verify(token);
        final open = await verifier.verify(token);
        now = now.add(const Duration(seconds: 11));
        final afterWindow = await verifier.verify(token);

        expect(first.isError(), isTrue);
        expect(open.isError(), isTrue);
        expect(afterWindow.isError(), isTrue);
        final openFailure = open.exceptionOrNull()! as domain.Failure;
        final afterWindowFailure = afterWindow.exceptionOrNull()! as domain.Failure;
        expect(openFailure.context['reason'], equals('jwks_circuit_open'));
        expect(
          afterWindowFailure.context['reason'],
          isNot('jwks_circuit_open'),
        );
      },
    );
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
