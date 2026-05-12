import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';

void main() {
  group('PayloadSigningConfig', () {
    test('should upsert key and make it active for rotation', () {
      final config = PayloadSigningConfig(
        activeKeyId: 'v1',
        keys: const <String, String>{'v1': 'old-secret'},
      );

      final rotated = config.upsertKey(
        keyId: 'v2',
        secret: 'new-secret',
        makeActive: true,
      );

      expect(rotated.activeKeyId, equals('v2'));
      expect(rotated.keyIds, equals(<String>['v1', 'v2']));
      expect(rotated.keys['v2'], equals('new-secret'));
    });

    test('should reject activating missing key', () {
      final config = PayloadSigningConfig(
        activeKeyId: 'v1',
        keys: const <String, String>{'v1': 'secret'},
      );

      expect(() => config.activateKey('v2'), throwsArgumentError);
    });

    test('should move active key when removing current active key', () {
      final config = PayloadSigningConfig(
        activeKeyId: 'v2',
        keys: const <String, String>{
          'v1': 'old-secret',
          'v2': 'new-secret',
        },
      );

      final next = config.removeKey('v2');

      expect(next.activeKeyId, equals('v1'));
      expect(next.keyIds, equals(<String>['v1']));
    });
  });
}
