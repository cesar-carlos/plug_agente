import 'package:plug_agente/domain/backup/local_backup_error_codes.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

String localizedBackupFailureMessage(Failure failure, AppLocalizations l10n) {
  final code = failure.context[LocalBackupErrorCodes.contextKey] as String?;
  return switch (code) {
    LocalBackupErrorCodes.missingManifestOrDb => l10n.configBackupErrMissingManifestOrDb,
    LocalBackupErrorCodes.invalidManifest => l10n.configBackupErrInvalidManifest,
    LocalBackupErrorCodes.unsupportedFormat => l10n.configBackupErrUnsupportedFormat,
    LocalBackupErrorCodes.dbVersion => l10n.configBackupErrDbVersion,
    LocalBackupErrorCodes.newerBackup => l10n.configBackupErrNewerBackup,
    LocalBackupErrorCodes.invalidEntry => l10n.configBackupErrInvalidEntry,
    LocalBackupErrorCodes.exportDbNotFound => l10n.configBackupErrExportDbNotFound,
    LocalBackupErrorCodes.exportZip => l10n.configBackupErrExportZip,
    LocalBackupErrorCodes.exportWrite => l10n.configBackupErrExportWrite,
    LocalBackupErrorCodes.exportGeneric => l10n.configBackupErrExportGeneric,
    LocalBackupErrorCodes.readZip => l10n.configBackupErrReadZip,
    LocalBackupErrorCodes.stageGeneric => l10n.configBackupErrStageGeneric,
    LocalBackupErrorCodes.applyMissingDb => l10n.configBackupErrApplyMissingDb,
    LocalBackupErrorCodes.applyWrite => l10n.configBackupErrApplyWrite,
    LocalBackupErrorCodes.exportSecretsUnavailable => l10n.configBackupErrExportSecretsUnavailable,
    LocalBackupErrorCodes.exportSecretsEncrypt => l10n.configBackupErrExportSecretsEncrypt,
    LocalBackupErrorCodes.restoreSecretsDecrypt => l10n.configBackupErrRestoreSecretsDecrypt,
    LocalBackupErrorCodes.restoreSecretsApply => l10n.configBackupErrRestoreSecretsApply,
    _ => failure.message,
  };
}
