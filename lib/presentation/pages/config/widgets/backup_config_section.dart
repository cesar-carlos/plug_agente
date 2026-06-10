import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/backup/local_data_backup.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_failures;
import 'package:plug_agente/domain/repositories/i_local_app_data_backup_service.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/backup_failure_localizer.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/feedback/inline_feedback_card.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';

class BackupConfigSection extends StatefulWidget {
  const BackupConfigSection({super.key});

  @override
  State<BackupConfigSection> createState() => _BackupConfigSectionState();
}

class _BackupConfigSectionState extends State<BackupConfigSection> {
  bool _busy = false;
  bool _includeSecureStorageSecrets = false;
  String? _busySemanticsLabel;
  String? _pendingRestoreFailure;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPendingRestoreFailure());
  }

  Future<void> _loadPendingRestoreFailure() async {
    if (!getIt.isRegistered<ILocalAppDataBackupService>()) {
      return;
    }
    final diagnostics = await getIt<ILocalAppDataBackupService>().readPendingRestoreFailureDiagnostics();
    if (!mounted || diagnostics == null) {
      return;
    }
    setState(() => _pendingRestoreFailure = diagnostics);
  }

  Future<void> _dismissRestoreFailure() async {
    setState(() => _pendingRestoreFailure = null);
    if (getIt.isRegistered<ILocalAppDataBackupService>()) {
      await getIt<ILocalAppDataBackupService>().clearRestoreFailureDiagnostics();
    }
  }

  String _failureMessage(Object failure, AppLocalizations l10n) {
    if (failure is domain_failures.Failure) {
      return localizedBackupFailureMessage(failure, l10n);
    }
    return failure.toString();
  }

  Future<void> _setBusy({required bool value, String? semanticsLabel}) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = value;
      _busySemanticsLabel = semanticsLabel;
    });
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: l10n.configBackupButtonExport,
        fileName: 'plug_agente_backup.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (path == null || !mounted) {
        return;
      }

      await _setBusy(value: true, semanticsLabel: l10n.configBackupExporting);
      final result = await getIt<ILocalAppDataBackupService>().exportBackupZip(
        path,
        includeSecureStorageSecrets: _includeSecureStorageSecrets,
      );
      await _setBusy(value: false);

      if (!mounted) {
        return;
      }

      if (result.isError()) {
        await SettingsFeedback.showError(
          context: context,
          title: l10n.configBackupExportFailedTitle,
          message: _failureMessage(result.exceptionOrNull()!, l10n),
        );
        return;
      }

      await SettingsFeedback.showSuccess(
        context: context,
        title: l10n.configBackupExportSuccessTitle,
        message:
            '${l10n.configBackupExportSuccessMessage}\n\n${_includeSecureStorageSecrets ? l10n.configBackupExportSecretsIncludedNote : l10n.configBackupExportSecretsNotIncludedNote}',
      );
    } on Exception catch (e, st) {
      developer.log('backup export failed', name: 'backup_config_section', error: e, stackTrace: st);
      await _setBusy(value: false);
      if (mounted) {
        await SettingsFeedback.showError(
          context: context,
          title: l10n.configBackupExportFailedTitle,
          message: l10n.configBackupErrExportGeneric,
        );
      }
    }
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context)!;
    final service = getIt<ILocalAppDataBackupService>();

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        dialogTitle: l10n.configBackupButtonRestore,
      );
    } on Exception catch (e, st) {
      developer.log('restore picker failed', name: 'backup_config_section', error: e, stackTrace: st);
      if (mounted) {
        await SettingsFeedback.showError(
          context: context,
          title: l10n.configBackupRestoreFailedTitle,
          message: l10n.configBackupErrReadZip,
        );
      }
      return;
    }

    final path = picked?.files.single.path;
    if (path == null || !mounted) {
      return;
    }

    await _setBusy(value: true, semanticsLabel: l10n.configBackupRestoring);
    final stageResult = await service.stageRestoreFromZip(path);
    await _setBusy(value: false);

    if (!mounted) {
      return;
    }

    if (stageResult.isError()) {
      await SettingsFeedback.showError(
        context: context,
        title: l10n.configBackupRestoreFailedTitle,
        message: _failureMessage(stageResult.exceptionOrNull()!, l10n),
      );
      return;
    }

    final staging = stageResult.getOrThrow();
    final appSchemaVersion = getIt<ILocalAppDataBackupService>().liveAgentConfigSchemaVersion;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return _RestoreConfirmDialog(
          staging: staging,
          l10n: l10n,
          appSchemaVersion: appSchemaVersion,
        );
      },
    );

    if (confirmed != true) {
      service.disposeStaging(staging);
      return;
    }

    await getIt<IAppSettingsStore>().flushPendingPersistence();
    await shutdownApp();

    final applyResult = await service.applyRestore(staging);
    service.disposeStaging(staging);

    if (applyResult.isError()) {
      final failure = applyResult.exceptionOrNull()!;
      developer.log(
        'applyRestore failed after shutdown',
        name: 'backup_config_section',
        error: failure,
      );
      await service.writeRestoreFailureDiagnostics(failure);
      exit(1);
    }

    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      child: SettingsSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_pendingRestoreFailure case final String diagnostics) ...[
              InfoBar(
                key: const ValueKey('restore_failure_notice'),
                title: Text(l10n.configBackupRestoreFailedNoticeTitle),
                severity: InfoBarSeverity.error,
                isLong: true,
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.configBackupRestoreFailedNoticeBody),
                    const SizedBox(height: AppSpacing.sm),
                    Expander(
                      header: Text(l10n.configBackupRestoreFailedDetailsHeader),
                      content: SelectableText(
                        diagnostics,
                        key: const ValueKey('restore_failure_details'),
                        style: context.captionText,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AppButton(
                        key: const ValueKey('restore_failure_dismiss_button'),
                        label: l10n.configBackupRestoreFailedNoticeDismiss,
                        isPrimary: false,
                        onPressed: () => unawaited(_dismissRestoreFailure()),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            SettingsSectionTitle(title: l10n.configBackupSectionTitle),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.configBackupIntro, style: context.bodyText),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.configBackupDuplicateNote, style: context.captionText),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.configBackupSingleInstanceNote, style: context.captionText),
            if (l10n.localeName.startsWith('pt')) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(AppStrings.singleInstanceMessage, style: context.captionText),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.configBackupRestoreDiagnosticsHint(AppConstants.lastRestoreErrorFileName),
              style: context.captionText,
            ),
            const SizedBox(height: AppSpacing.md),
            InlineFeedbackCard(
              key: const ValueKey('backup_secure_storage_secrets_notice'),
              severity: InfoBarSeverity.info,
              message: l10n.configBackupSecureStorageSecretsNote,
            ),
            const SizedBox(height: AppSpacing.sm),
            Checkbox(
              key: const ValueKey('backup_include_secure_storage_secrets_checkbox'),
              checked: _includeSecureStorageSecrets,
              onChanged: _busy
                  ? null
                  : (bool? value) => setState(() => _includeSecureStorageSecrets = value ?? false),
              content: Text(l10n.configBackupIncludeSecureStorageSecretsLabel),
            ),
            if (_includeSecureStorageSecrets) ...[
              const SizedBox(height: AppSpacing.sm),
              InlineFeedbackCard(
                key: const ValueKey('backup_include_secure_storage_secrets_warning'),
                severity: InfoBarSeverity.warning,
                message: l10n.configBackupIncludeSecureStorageSecretsWarning,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Tooltip(
                  message: l10n.configBackupButtonExport,
                  child: Semantics(
                    button: true,
                    label: l10n.configBackupButtonExport,
                    child: AppButton(
                      label: l10n.configBackupButtonExport,
                      isPrimary: false,
                      onPressed: _busy ? null : _export,
                    ),
                  ),
                ),
                Tooltip(
                  message: l10n.configBackupButtonRestore,
                  child: Semantics(
                    button: true,
                    label: l10n.configBackupButtonRestore,
                    child: AppButton(
                      label: l10n.configBackupButtonRestore,
                      isDestructive: true,
                      onPressed: _busy ? null : _restore,
                    ),
                  ),
                ),
                if (_busy)
                  Semantics(
                    label: _busySemanticsLabel ?? l10n.configBackupRestoring,
                    child: const SizedBox(
                      width: 22,
                      height: 22,
                      child: ProgressRing(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RestoreConfirmDialog extends StatefulWidget {
  const _RestoreConfirmDialog({
    required this.staging,
    required this.l10n,
    required this.appSchemaVersion,
  });

  final RestoreStagingSnapshot staging;
  final AppLocalizations l10n;
  final int appSchemaVersion;

  @override
  State<_RestoreConfirmDialog> createState() => _RestoreConfirmDialogState();
}

class _RestoreConfirmDialogState extends State<_RestoreConfirmDialog> {
  bool _ackDuplicate = false;
  bool _ackUncertain = false;

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final staging = widget.staging;

    final needsDup = staging.duplicateRisk == DuplicateRiskLevel.agentListedAsConnectedOnHub;
    final needsUncertain = staging.duplicateRisk == DuplicateRiskLevel.verificationImpossible;
    final canProceed = (!needsDup || _ackDuplicate) && (!needsUncertain || _ackUncertain);

    final installationMismatch =
        staging.manifestInstallationId != null &&
        staging.currentInstallationId != null &&
        staging.manifestInstallationId != staging.currentInstallationId;

    final olderSchema = staging.backupUserVersion < widget.appSchemaVersion;

    final width = MediaQuery.sizeOf(context).width;
    final dialogWidth = width > 640 ? 520.0 : width * 0.92;

    return ContentDialog(
      title: Text(l10n.configBackupRestoreDialogTitle),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.configBackupRestoreDialogBody, style: context.bodyText),
              const SizedBox(height: AppSpacing.md),
              if (olderSchema) ...[
                Text(l10n.configBackupRestoreOlderSchemaNote, style: context.captionText),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (installationMismatch) ...[
                Text(l10n.configBackupRestoreInstallationMismatch, style: context.captionText),
                const SizedBox(height: AppSpacing.sm),
              ],
              InlineFeedbackCard(
                key: ValueKey(
                  staging.manifestSecureStorageSecretsIncluded
                      ? 'restore_secure_storage_secrets_included_notice'
                      : 'restore_odbc_secrets_warning',
                ),
                severity: staging.manifestSecureStorageSecretsIncluded
                    ? InfoBarSeverity.info
                    : InfoBarSeverity.warning,
                message: staging.manifestSecureStorageSecretsIncluded
                    ? l10n.configBackupRestoreSecretsIncludedNote
                    : l10n.configBackupRestoreOdbcSecretsWarning,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.configBackupRestoreRestartNotice, style: context.captionText),
              const SizedBox(height: AppSpacing.md),
              if (needsDup) ...[
                Text(l10n.configBackupRestoreDuplicateWarning, style: context.captionText),
                Checkbox(
                  checked: _ackDuplicate,
                  onChanged: (bool? v) => setState(() => _ackDuplicate = v ?? false),
                  content: Text(l10n.configBackupCheckboxAcknowledgeDuplicate),
                ),
              ],
              if (needsUncertain) ...[
                Text(l10n.configBackupRestoreVerifyWarning, style: context.captionText),
                Checkbox(
                  checked: _ackUncertain,
                  onChanged: (bool? v) => setState(() => _ackUncertain = v ?? false),
                  content: Text(l10n.configBackupCheckboxAcknowledgeUncertain),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: l10n.configBackupCancel,
          isPrimary: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: l10n.configBackupRestoreConfirm,
          onPressed: canProceed ? () => Navigator.of(context).pop(true) : null,
        ),
      ],
    );
  }
}
