import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/infrastructure/security/payload_signing_key_resolver.dart';

class _FakePayloadSigningKeyStore implements PayloadSigningKeyStore {
  _FakePayloadSigningKeyStore({
    PayloadSigningConfig? initial,
  }) : saved = initial;

  PayloadSigningConfig? saved;
  int saveCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<PayloadSigningConfig?> read() async => saved;

  @override
  Future<void> save(PayloadSigningConfig config) async {
    saveCalls++;
    saved = config;
  }
}

void main() {
  group('PayloadSigningKeyResolver', () {
    test('loads legacy environment key and persists it to secure storage', () async {
      final store = _FakePayloadSigningKeyStore();
      final resolver = PayloadSigningKeyResolver(
        keyStore: store,
        environmentProvider: (key) => switch (key) {
          'PAYLOAD_SIGNING_KEY_ID' => 'key-1',
          'PAYLOAD_SIGNING_KEY' => 'secret-1',
          _ => null,
        },
      );

      final config = await resolver.resolve();

      check(config.hasConfiguredSigner).isTrue();
      check(config.activeKeyId).equals('key-1');
      check(config.keys['key-1']).equals('secret-1');
      check(config.source).equals(PayloadSigningConfigSource.environment);
      check(store.saveCalls).equals(1);
    });

    test('loads secure storage when environment is absent', () async {
      final store = _FakePayloadSigningKeyStore(
        initial: PayloadSigningConfig(
          activeKeyId: 'key-secure',
          keys: {'key-secure': 'secure-secret'},
          source: PayloadSigningConfigSource.secureStorage,
        ),
      );
      final resolver = PayloadSigningKeyResolver(
        keyStore: store,
        environmentProvider: (_) => null,
      );

      final config = await resolver.resolve();

      check(config.hasConfiguredSigner).isTrue();
      check(config.activeKeyId).equals('key-secure');
      check(config.keys['key-secure']).equals('secure-secret');
      check(config.source).equals(PayloadSigningConfigSource.secureStorage);
      check(store.saveCalls).equals(0);
    });

    test('merges environment rotation keys with stored previous keys', () async {
      final store = _FakePayloadSigningKeyStore(
        initial: PayloadSigningConfig(
          activeKeyId: 'old-key',
          keys: {'old-key': 'old-secret'},
        ),
      );
      final resolver = PayloadSigningKeyResolver(
        keyStore: store,
        environmentProvider: (key) => switch (key) {
          'PAYLOAD_SIGNING_KEYS_JSON' => '{"new-key":"new-secret"}',
          'PAYLOAD_SIGNING_ACTIVE_KEY_ID' => 'new-key',
          _ => null,
        },
      );

      final config = await resolver.resolve();

      check(config.activeKeyId).equals('new-key');
      check(config.keys['old-key']).equals('old-secret');
      check(config.keys['new-key']).equals('new-secret');
      check(config.source).equals(PayloadSigningConfigSource.environmentAndSecureStorage);
      check(store.saveCalls).equals(1);
    });

    test('reports incomplete legacy environment configuration', () async {
      final store = _FakePayloadSigningKeyStore();
      final resolver = PayloadSigningKeyResolver(
        keyStore: store,
        environmentProvider: (key) => key == 'PAYLOAD_SIGNING_KEY' ? 'secret-only' : null,
      );

      final config = await resolver.resolve();

      check(config.hasConfiguredSigner).isFalse();
      check(config.warnings).contains('payload_signing_legacy_key_incomplete');
      check(store.saveCalls).equals(0);
    });
  });
}
