import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jose/jose.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';

void main() {
  group('JwtJwksVerifier', () {
    for (final header in <Object?>[
      [],
      null,
      {'alg': 42},
      {
        'alg': {'value': 'RS256'},
      },
    ]) {
      test('rejects malformed JWT header $header without consulting JWKS or opening circuit', () async {
        var storeBuilds = 0;
        final verifier = JwtJwksVerifier(
          () async => const JwksConfig(jwksUrl: 'https://example.com/jwks.json'),
          failureThreshold: 1,
          createKeyStore: (_) {
            storeBuilds++;
            return JsonWebKeyStore();
          },
        );
        final encodedHeader = base64Url.encode(utf8.encode(jsonEncode(header)));
        final token = '$encodedHeader.e30.sig';

        for (var attempt = 0; attempt < 2; attempt++) {
          final result = await verifier.verify(token);
          final failure = result.exceptionOrNull()! as domain.ConfigurationFailure;
          expect(failure.context['reason'], AuthorizationContextConstants.invalidTokenSignatureReason);
        }
        expect(storeBuilds, 0);
      });
    }

    test('maps configuration read failure and permits retry after circuit expires', () async {
      var now = DateTime.utc(2026);
      var configReads = 0;
      final cause = Exception('storage unavailable');
      final verifier = JwtJwksVerifier(
        () async {
          configReads++;
          throw cause;
        },
        failureThreshold: 1,
        circuitOpenDuration: const Duration(seconds: 10),
        now: () => now,
      );

      final first = await verifier.verify('any-token');
      final failure = first.exceptionOrNull()! as domain.ConfigurationFailure;
      expect(failure.cause, same(cause));
      expect(failure.context['reason'], AuthorizationContextConstants.invalidJwksConfigReason);
      expect(failure.context['user_message'], isNotEmpty);
      final blocked = await verifier.verify('any-token');
      expect(
        (blocked.exceptionOrNull()! as domain.ConfigurationFailure).context['reason'],
        AuthorizationContextConstants.jwksCircuitOpenReason,
      );
      expect(configReads, 1);
      now = now.add(const Duration(seconds: 11));
      await verifier.verify('any-token');
      expect(configReads, 2);
    });

    final signedKey = JsonWebKey.generate('ES256');
    String signClaims(Map<String, dynamic> claims) {
      final builder = JsonWebSignatureBuilder()..jsonContent = claims;
      builder.addRecipient(signedKey, algorithm: 'ES256');
      return builder.build().toCompactSerialization();
    }

    for (final entry in <MapEntry<String, Object?>>[
      const MapEntry('kid', 42),
      const MapEntry('cty', 42),
      const MapEntry('typ', 42),
      const MapEntry('jku', 42),
      const MapEntry('enc', 42),
      const MapEntry('zip', 42),
      const MapEntry('crit', 'kid'),
      const MapEntry('crit', [42]),
      const MapEntry('jwk', 'key'),
      const MapEntry('kid', null),
    ]) {
      test('rejects malformed signed header ${entry.key} ${entry.value} before key access', () async {
        var storeBuilds = 0;
        final verifier = JwtJwksVerifier(
          () async => const JwksConfig(jwksUrl: 'https://local.invalid/jwks'),
          failureThreshold: 1,
          createKeyStore: (_) {
            storeBuilds++;
            return JsonWebKeyStore()..addKey(signedKey);
          },
        );
        final builder = JsonWebSignatureBuilder()..jsonContent = {'sub': 'client'};
        builder.setProtectedHeader(entry.key, entry.value);
        builder.addRecipient(signedKey, algorithm: 'ES256');
        final token = builder.build().toCompactSerialization();
        for (var attempt = 0; attempt < 2; attempt++) {
          final failure = (await verifier.verify(token)).exceptionOrNull()! as domain.ConfigurationFailure;
          expect(failure.context['reason'], AuthorizationContextConstants.invalidTokenSignatureReason);
        }
        expect(storeBuilds, 0);
        expect((await verifier.verify(signClaims({'sub': 'client'}))).isSuccess(), isTrue);
      });
    }

    test('accepts valid key ID and content type with configured keys only', () async {
      final identifiedKey = JsonWebKey.fromJson({...signedKey.toJson(), 'kid': 'local-key'});
      final builder = JsonWebSignatureBuilder()..jsonContent = {'sub': 'client'};
      builder.setProtectedHeader('cty', 'application/json');
      builder.setProtectedHeader('typ', 'JWT');
      builder.setProtectedHeader('jku', 'https://untrusted.invalid/keys');
      builder.addRecipient(identifiedKey, algorithm: 'ES256');
      final verifier = JwtJwksVerifier(
        () async => const JwksConfig(jwksUrl: 'https://local.invalid/jwks'),
        createKeyStore: (_) => JsonWebKeyStore()..addKey(identifiedKey),
      );
      expect((await verifier.verify(builder.build().toCompactSerialization())).getOrThrow()['sub'], 'client');
    });

    for (final url in [
      'not-a-url',
      'file:///C:/keys.json',
      'ftp://local.invalid/jwks',
      'https:/keys',
      'https://',
      'http://[',
    ]) {
      test('maps invalid JWKS URL $url to actionable failure without key access or circuit', () async {
        var storeBuilds = 0;
        var currentUrl = url;
        final verifier = JwtJwksVerifier(
          () async => JwksConfig(jwksUrl: currentUrl),
          failureThreshold: 1,
          createKeyStore: (_) {
            storeBuilds++;
            return JsonWebKeyStore()..addKey(signedKey);
          },
        );
        final token = signClaims({'sub': 'client'});
        for (var attempt = 0; attempt < 2; attempt++) {
          final failure = (await verifier.verify(token)).exceptionOrNull()! as domain.ConfigurationFailure;
          expect(failure.context['reason'], AuthorizationContextConstants.invalidJwksConfigReason);
          expect(failure.context['user_message'], contains('URL JWKS invalida'));
          expect(failure.isTransient, isFalse);
        }
        expect(storeBuilds, 0);
        currentUrl = 'https://local.invalid/jwks';
        expect((await verifier.verify(token)).isSuccess(), isTrue);
      });
    }

    for (final entry in <MapEntry<String, Object>>[
      const MapEntry('iss', 42),
      const MapEntry('iss', ['issuer']),
      const MapEntry('aud', 42),
      const MapEntry('aud', [42]),
      const MapEntry('aud', {'value': 'agent'}),
    ]) {
      test('rejects malformed signed ${entry.key} ${entry.value} through Result without opening circuit', () async {
        final verifier = JwtJwksVerifier(
          () async =>
              const JwksConfig(jwksUrl: 'https://local.invalid/jwks', issuer: 'https://issuer', audience: 'agent'),
          failureThreshold: 1,
          createKeyStore: (_) => JsonWebKeyStore()..addKey(signedKey),
        );
        final token = signClaims({'iss': 'https://issuer', 'aud': 'agent', entry.key: entry.value});
        for (var i = 0; i < 2; i++) {
          final failure = (await verifier.verify(token)).exceptionOrNull()! as domain.ConfigurationFailure;
          expect(failure.context['reason'], AuthorizationContextConstants.invalidTokenSignatureReason);
          expect(failure.context['user_message'], isNotEmpty);
        }
        expect(
          (await verifier.verify(
            signClaims({
              'iss': 'https://issuer',
              'aud': ['agent', 'other'],
            }),
          )).isSuccess(),
          isTrue,
        );
      });
    }

    test('accepts both supported audience shapes and rejects a different audience', () async {
      final verifier = JwtJwksVerifier(
        () async =>
            const JwksConfig(jwksUrl: 'https://local.invalid/jwks', issuer: 'https://issuer', audience: 'agent'),
        createKeyStore: (_) => JsonWebKeyStore()..addKey(signedKey),
      );
      for (final audience in <Object>[
        'agent',
        ['other', 'agent'],
      ]) {
        expect((await verifier.verify(signClaims({'iss': 'https://issuer', 'aud': audience}))).isSuccess(), isTrue);
      }
      expect((await verifier.verify(signClaims({'iss': 'https://issuer', 'aud': 'other'}))).isError(), isTrue);
    });

    for (final oldReadFails in [false, true]) {
      test('trust change discards an old pending config ${oldReadFails ? 'failure' : 'snapshot'}', () async {
        final pendingConfig = Completer<JwksConfig?>();
        var reads = 0;
        final verifier = JwtJwksVerifier(
          () {
            reads++;
            return reads == 1
                ? pendingConfig.future
                : Future.value(const JwksConfig(jwksUrl: 'https://new.invalid/jwks', issuer: 'https://new-issuer'));
          },
          failureThreshold: 1,
          createKeyStore: (_) => JsonWebKeyStore()..addKey(signedKey),
        );
        final pending = verifier.verify(signClaims({'iss': 'https://old-issuer'}));
        verifier.invalidateTrust();
        if (oldReadFails) {
          pendingConfig.completeError(Exception('old configuration unavailable'));
        } else {
          pendingConfig.complete(const JwksConfig(jwksUrl: 'https://old.invalid/jwks', issuer: 'https://old-issuer'));
        }
        final rejected = (await pending).exceptionOrNull()! as domain.ConfigurationFailure;
        expect(rejected.context['reason'], AuthorizationContextConstants.invalidTokenSignatureReason);
        expect((await verifier.verify(signClaims({'iss': 'https://new-issuer'}))).isSuccess(), isTrue);
      });
    }

    test('invalid signatures do not block a subsequently valid credential', () async {
      final wrongKey = JsonWebKey.generate('ES256');
      final badBuilder = JsonWebSignatureBuilder()..jsonContent = {'sub': 'client'};
      badBuilder.addRecipient(wrongKey, algorithm: 'ES256');
      final invalid = badBuilder.build().toCompactSerialization();
      final verifier = JwtJwksVerifier(
        () async => const JwksConfig(jwksUrl: 'https://local.invalid/jwks'),
        createKeyStore: (_) => JsonWebKeyStore()..addKey(signedKey),
      );
      for (var i = 0; i < 4; i++) {
        final failure = (await verifier.verify(invalid)).exceptionOrNull()! as domain.ConfigurationFailure;
        expect(failure.context['reason'], AuthorizationContextConstants.invalidTokenSignatureReason);
      }
      expect((await verifier.verify(signClaims({'sub': 'client'}))).isSuccess(), isTrue);
    });

    test('malformed payloads do not consume the infrastructure circuit', () async {
      final verifier = JwtJwksVerifier(
        () async => const JwksConfig(jwksUrl: 'https://local.invalid/jwks'),
        failureThreshold: 1,
        createKeyStore: (_) => JsonWebKeyStore()..addKey(signedKey),
      );
      final valid = signClaims({'sub': 'client'});
      final header = valid.split('.').first;
      for (final token in ['$header.${_b64('[]')}.sig', '$header.invalid!.sig', '$header.sig']) {
        expect((await verifier.verify(token)).isError(), isTrue);
      }
      expect((await verifier.verify(valid)).isSuccess(), isTrue);
    });

    test('issuer mismatch diagnostics do not expose the supplied issuer', () async {
      final verifier = JwtJwksVerifier(
        () async => const JwksConfig(jwksUrl: 'https://local.invalid/jwks', issuer: 'https://issuer'),
        createKeyStore: (_) => JsonWebKeyStore()..addKey(signedKey),
      );
      final failure =
          (await verifier.verify(signClaims({'iss': 'sensitive-value'}))).exceptionOrNull()!
              as domain.ConfigurationFailure;
      expect(failure.message, isNot(contains('sensitive-value')));
      expect(failure.context['reason'], AuthorizationContextConstants.invalidTokenSignatureReason);
    });

    test('rejects at the exact signed expiration instant', () async {
      final now = DateTime.utc(2026, 10, 8);
      final verifier = JwtJwksVerifier(
        () async => const JwksConfig(jwksUrl: 'https://local.invalid/jwks'),
        now: () => now,
        createKeyStore: (_) => JsonWebKeyStore()..addKey(signedKey),
      );
      final token = signClaims({'exp': now.millisecondsSinceEpoch ~/ 1000});
      final result = await verifier.verify(token);
      expect(
        (result.exceptionOrNull()! as domain.ConfigurationFailure).context['reason'],
        AuthorizationContextConstants.tokenExpiredReason,
      );
    });

    for (final fraction in [0.25, 0.75]) {
      test('preserves fractional expiration $fraction without rounding to a second', () async {
        final base = DateTime.utc(2026, 10, 8);
        var now = base;
        final expiry = base.add(Duration(microseconds: (fraction * 1000000).toInt()));
        final verifier = JwtJwksVerifier(
          () async => const JwksConfig(jwksUrl: 'https://local.invalid/jwks'),
          now: () => now,
          createKeyStore: (_) => JsonWebKeyStore()..addKey(signedKey),
        );
        final token = signClaims({'exp': base.millisecondsSinceEpoch ~/ 1000 + fraction});
        now = expiry.subtract(const Duration(microseconds: 1));
        expect((await verifier.verify(token)).isSuccess(), isTrue);
        now = expiry;
        expect((await verifier.verify(token)).isError(), isTrue);
      });

      test('preserves fractional not-before $fraction and accepts its exact boundary', () async {
        final base = DateTime.utc(2026, 10, 8);
        var now = base;
        final activation = base.add(Duration(microseconds: (fraction * 1000000).toInt()));
        final verifier = JwtJwksVerifier(
          () async => const JwksConfig(jwksUrl: 'https://local.invalid/jwks'),
          now: () => now,
          createKeyStore: (_) => JsonWebKeyStore()..addKey(signedKey),
        );
        final token = signClaims({'nbf': base.millisecondsSinceEpoch ~/ 1000 + fraction});
        now = activation.subtract(const Duration(microseconds: 1));
        expect((await verifier.verify(token)).isError(), isTrue);
        now = activation;
        expect((await verifier.verify(token)).isSuccess(), isTrue);
      });
    }

    for (final claim in ['exp', 'nbf']) {
      for (final value in <Object>['sensitive-value', 1e100]) {
        test('maps malformed signed $claim claim without opening the circuit', () async {
          final verifier = JwtJwksVerifier(
            () async => const JwksConfig(jwksUrl: 'https://local.invalid/jwks'),
            now: () => DateTime.utc(2026, 10, 8),
            failureThreshold: 1,
            createKeyStore: (_) => JsonWebKeyStore()..addKey(signedKey),
          );
          final token = signClaims({claim: value});
          for (var attempt = 0; attempt < 2; attempt++) {
            final result = await verifier.verify(token);
            final failure = result.exceptionOrNull()! as domain.ConfigurationFailure;
            expect(failure.context['reason'], AuthorizationContextConstants.invalidTokenSignatureReason);
            expect(failure.message, isNot(contains('sensitive-value')));
          }
        });
      }
    }

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
      'should use createKeyStore when resolving JWKS before verify fails',
      () async {
        var storeBuilds = 0;
        final verifier = JwtJwksVerifier(
          () async => const JwksConfig(jwksUrl: 'https://example.com/jwks.json'),
          createKeyStore: (u) {
            storeBuilds++;
            return JsonWebKeyStore()..addKeySetUrl(u);
          },
        );

        final token = _buildTokenWithAlg('RS256');
        final result = await verifier.verify(token);

        expect(result.isError(), isTrue);
        expect(storeBuilds, 1);
      },
    );

    test(
      'should open JWKS circuit breaker after consecutive failures',
      () async {
        final now = DateTime.utc(2026, 3, 17, 12);
        final token = signClaims({'sub': 'client'});
        final verifier = JwtJwksVerifier(
          () async => const JwksConfig(jwksUrl: 'https://example.com/jwks.json'),
          failureThreshold: 2,
          now: () => now,
          createKeyStore: (_) => _FailingKeyStore(),
        );

        final first = await verifier.verify(token);
        final second = await verifier.verify(token);
        final third = await verifier.verify(token);

        expect(first.isError(), isTrue);
        expect((first.exceptionOrNull()! as domain.Failure).cause, isA<SocketException>());
        expect(second.isError(), isTrue);
        expect(third.isError(), isTrue);
        final failure = third.exceptionOrNull()! as domain.Failure;
        expect(failure.context['reason'], equals(AuthorizationContextConstants.jwksCircuitOpenReason));
      },
    );

    test(
      'should close JWKS circuit breaker after open duration expires',
      () async {
        var now = DateTime.utc(2026, 3, 17, 12);
        final token = signClaims({'sub': 'client'});
        final verifier = JwtJwksVerifier(
          () async => const JwksConfig(jwksUrl: 'https://example.com/jwks.json'),
          failureThreshold: 1,
          circuitOpenDuration: const Duration(seconds: 10),
          now: () => now,
          createKeyStore: (_) => _FailingKeyStore(),
        );

        final first = await verifier.verify(token);
        final open = await verifier.verify(token);
        now = now.add(const Duration(seconds: 10));
        final afterWindow = await verifier.verify(token);

        expect(first.isError(), isTrue);
        expect(open.isError(), isTrue);
        expect(afterWindow.isError(), isTrue);
        final openFailure = open.exceptionOrNull()! as domain.Failure;
        final afterWindowFailure = afterWindow.exceptionOrNull()! as domain.Failure;
        expect(openFailure.context['reason'], equals(AuthorizationContextConstants.jwksCircuitOpenReason));
        expect(
          afterWindowFailure.context['reason'],
          isNot(AuthorizationContextConstants.jwksCircuitOpenReason),
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

class _FailingKeyStore extends JsonWebKeyStore {
  @override
  Stream<JsonWebKey?> findJsonWebKeys(JoseHeader header, String operation) =>
      Stream.error(const SocketException('injected JWKS connection failure'));
}
