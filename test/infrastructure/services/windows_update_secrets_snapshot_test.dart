import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/services/windows_update_secrets_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('captures action and payload namespaces and restores exact owned entries', () async {
    FlutterSecureStorage.setMockInitialValues({
      'agent_action_secret_email': 'original',
      'payload_signing_keys_json': '{"a":"value"}',
      'odbc_credential_secret_db': 'db',
      'other_application_password': 'untouched',
    });
    final snapshots = WindowsUpdateSecretsSnapshot(transform: (value, _) async => value);
    final captured = (await snapshots.captureEncrypted()).getOrThrow();
    expect((jsonDecode(captured) as Map)['entries'], isNot(contains('other_application_password')));
    const storage = FlutterSecureStorage();
    await storage.write(key: 'agent_action_secret_email', value: 'changed');
    await storage.write(key: 'hub_auth_secret_new', value: 'new');
    await storage.delete(key: 'payload_signing_keys_json');
    expect((await snapshots.restoreEncrypted(captured)).isSuccess(), isTrue);
    expect(await storage.read(key: 'agent_action_secret_email'), 'original');
    expect(await storage.read(key: 'hub_auth_secret_new'), isNull);
    expect(await storage.read(key: 'payload_signing_keys_json'), '{"a":"value"}');
    expect(await storage.read(key: 'other_application_password'), 'untouched');
  });
  test('unknown namespace is rejected before changing storage', () async {
    FlutterSecureStorage.setMockInitialValues({'odbc_credential_secret_db': 'original'});
    final snapshots = WindowsUpdateSecretsSnapshot(transform: (value, _) async => value);
    final valid = jsonDecode((await snapshots.captureEncrypted()).getOrThrow()) as Map<String, dynamic>;
    valid['entries'] = {'other_application_password': 'injected'};
    expect((await snapshots.restoreEncrypted(jsonEncode(valid))).isError(), isTrue);
    expect(await const FlutterSecureStorage().read(key: 'odbc_credential_secret_db'), 'original');
  });
}
