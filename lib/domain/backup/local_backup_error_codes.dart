/// Context key ([contextKey]) on the failure `context` map for backup UI localization.
abstract final class LocalBackupErrorCodes {
  static const String contextKey = 'backupError';

  static const String missingManifestOrDb = 'missing_manifest_or_db';
  static const String invalidManifest = 'invalid_manifest';
  static const String unsupportedFormat = 'unsupported_format';
  static const String dbVersion = 'db_version';
  static const String newerBackup = 'newer_backup';
  static const String invalidEntry = 'invalid_entry';
  static const String exportDbNotFound = 'export_db_not_found';
  static const String exportZip = 'export_zip';
  static const String exportWrite = 'export_write';
  static const String exportGeneric = 'export_generic';
  static const String readZip = 'read_zip';
  static const String stageGeneric = 'stage_generic';
  static const String applyMissingDb = 'apply_missing_db';
  static const String applyWrite = 'apply_write';
  static const String exportSecretsUnavailable = 'export_secrets_unavailable';
  static const String exportSecretsEncrypt = 'export_secrets_encrypt';
  static const String restoreSecretsDecrypt = 'restore_secrets_decrypt';
  static const String restoreSecretsApply = 'restore_secrets_apply';
}
