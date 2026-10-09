import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jose/jose.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/dio_jwks_key_store.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';

void main() {
  final key = JsonWebKey.generate('ES256');
  final publicKey = Map<String, dynamic>.from(key.toJson())..remove('d');
  final validBody = jsonEncode({
    'keys': [publicKey],
  });
  String sign(JsonWebKey signingKey) {
    final builder = JsonWebSignatureBuilder()..jsonContent = {'sub': 'client'};
    builder.addRecipient(signingKey, algorithm: 'ES256');
    return builder.build().toCompactSerialization();
  }

  final token = sign(key);
  late HttpServer server;
  late StreamSubscription<HttpRequest> subscription;
  late String body;
  late int status;
  late int requests;
  Future<void> Function(HttpRequest)? handle;
  setUp(() async {
    body = validBody;
    status = 200;
    requests = 0;
    handle = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    subscription = server.listen((request) async {
      requests++;
      if (handle != null) return handle!(request);
      request.response.statusCode = status;
      request.response.write(body);
      await request.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await subscription.cancel();
  });
  String url() => 'http://127.0.0.1:${server.port}/jwks';
  JwtJwksVerifier verifier() => JwtJwksVerifier(() async => JwksConfig(jwksUrl: url()));

  for (final errorBody in ['not-json', validBody]) {
    test('HTTP 500 is rejected and endpoint recovery is immediately visible', () async {
      status = 500;
      body = errorBody;
      final verification = verifier();
      final failure = (await verification.verify(token)).exceptionOrNull()! as domain.ConfigurationFailure;
      expect(failure.context['reason'], AuthorizationContextConstants.invalidJwksConfigReason);
      expect(failure.context['retryable'], isTrue);
      expect(failure.toString(), isNot(contains(errorBody)));
      expect(requests, 1);
      body = validBody;
      status = 200;
      expect((await verification.verify(token)).isSuccess(), isTrue);
      expect(requests, 2);
      expect((await verification.verify(token)).isSuccess(), isTrue);
      expect(requests, 2);
      verification.invalidateTrust();
      expect((await verification.verify(token)).isSuccess(), isTrue);
      expect(requests, 3);
    });
  }
  final malformedBodies = [
    'not-json',
    '[]',
    '{"keys":[]}',
    '{"keys":{}}',
    '{"keys":[42]}',
    '{"keys":[{}]}',
    jsonEncode({
      'keys': [
        {...publicKey, 'kid': 42},
      ],
    }),
    jsonEncode({
      'keys': [
        {
          ...publicKey,
          'key_ops': [42],
        },
      ],
    }),
    jsonEncode({
      'keys': [
        {...publicKey, 'crv': 'unknown'},
      ],
    }),
    jsonEncode({
      'keys': [
        {...publicKey, 'x': 42},
      ],
    }),
  ];
  for (var i = 0; i < malformedBodies.length; i++) {
    test('malformed HTTP 200 JWKS $i returns a typed failure without caching the body', () async {
      body = malformedBodies[i];
      final verification = verifier();
      expect((await verification.verify(token)).exceptionOrNull(), isA<domain.ConfigurationFailure>());
      body = validBody;
      expect((await verification.verify(token)).isSuccess(), isTrue);
      expect(requests, 2);
    });
  }
  test('valid keys are refreshed after configured TTL', () async {
    var now = DateTime.utc(2026);
    final verification = JwtJwksVerifier(() async => JwksConfig(jwksUrl: url()), now: () => now);
    expect((await verification.verify(token)).isSuccess(), isTrue);
    expect(requests, 1);
    now = now.add(const Duration(minutes: 4));
    expect((await verification.verify(token)).isSuccess(), isTrue);
    expect(requests, 1);
    now = now.add(const Duration(minutes: 2));
    expect((await verification.verify(token)).isSuccess(), isTrue);
    expect(requests, 2);
  });
  test('invalidated in-flight response cannot restore trust in the previous key', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final nextKey = JsonWebKey.generate('ES256');
    final nextBody = jsonEncode({
      'keys': [Map<String, dynamic>.from(nextKey.toJson())..remove('d')],
    });
    handle = (request) async {
      final first = requests == 1;
      if (first) {
        started.complete();
        await release.future;
      }
      request.response.write(first ? validBody : nextBody);
      await request.response.close();
    };
    final verification = verifier();
    final pending = verification.verify(token);
    await started.future;
    verification.invalidateTrust();
    release.complete();
    expect((await pending).isError(), isTrue);
    expect(requests, 2);
    expect((await verification.verify(sign(nextKey))).isSuccess(), isTrue);
  });
  test('a stalled HTTP request times out and can subsequently be retried', () async {
    final started = Completer<void>();
    handle = (_) async {
      started.complete();
    };
    final verification = JwtJwksVerifier(
      () async => JwksConfig(jwksUrl: url()),
      createKeyStore: (uri) => DioJwksKeyStore(uri, requestTimeout: const Duration(milliseconds: 100)),
    );
    final pending = verification.verify(token);
    await started.future;
    final failure = (await pending).exceptionOrNull()! as domain.ConfigurationFailure;
    expect(failure.context['retryable'], isTrue);
    handle = null;
    expect((await verification.verify(token)).isSuccess(), isTrue);
    expect(requests, 2);
  });
}
