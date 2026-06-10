/// Constants for optional encrypted secure-storage export in local backups.
abstract final class BackupSecureStorageSecretsConstants {
  static const int blobFormatVersion = 1;

  static const String zipEntryFileName = 'secure_storage_secrets.enc';

  /// App-specific key derivation input; must stay stable across app versions.
  static const String keyDerivationMaterial = 'plug_agente.local_backup.secure_storage_secrets.v1';

  /// flutter_secure_storage keys eligible for backup (ODBC, hub auth, client tokens).
  static const List<String> eligibleKeyPrefixes = <String>[
    'odbc_credential_secret_',
    'hub_auth_secret_',
    'client_token_secret_',
  ];
}
