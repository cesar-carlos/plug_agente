import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/backup/backup_secure_storage_secrets_cipher.dart';

void main() {
  test('encryptEntries round-trips eligible secure storage keys', () async {
    const entries = <String, String>{
      'odbc_credential_secret_cfg-1_password': 'odbc-secret',
      'hub_auth_secret_cfg-1_auth_token': 'hub-token',
      'client_token_secret_policy-a': 'client-token',
    };

    final encrypted = await BackupSecureStorageSecretsCipher.encryptEntries(entries);
    final decrypted = await BackupSecureStorageSecretsCipher.decryptEntries(encrypted);

    expect(decrypted, entries);
  });

  test('encrypted envelope does not contain plaintext secret values', () async {
    const secretValue = 'super-secret-password';
    final encrypted = await BackupSecureStorageSecretsCipher.encryptEntries(<String, String>{
      'odbc_credential_secret_cfg-1_password': secretValue,
    });

    final envelope = utf8.decode(encrypted);
    expect(envelope.contains(secretValue), isFalse);
  });

  test('decryptEntries rejects malformed envelope', () async {
    expect(
      () => BackupSecureStorageSecretsCipher.decryptEntries(Uint8List.fromList(utf8.encode('{}'))),
      throwsFormatException,
    );
  });
}
