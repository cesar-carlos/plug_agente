import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/policies/app_preferences_policy.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/support/support_diagnostics_section.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

class UpdateSupportDiagnosticsBuilder {
  const UpdateSupportDiagnosticsBuilder();

  SupportDiagnosticsSection buildPreferencesSection({
    required AppLocalizations l10n,
    required bool updateNotificationsEnabled,
    required bool automaticSilentUpdatesEnabled,
  }) {
    return SupportDiagnosticsSection(
      title: l10n.configUpdateTechnicalPreferencesTitle,
      fields: <SupportDiagnosticsField>[
        SupportDiagnosticsField(
          key: l10n.configUpdateTechnicalNotificationsEnabled,
          value: updateNotificationsEnabled
              ? l10n.configUpdateTechnicalOfficialFeedYes
              : l10n.configUpdateTechnicalOfficialFeedNo,
        ),
        SupportDiagnosticsField(
          key: l10n.configUpdateTechnicalAutomaticSilentEnabled,
          value: automaticSilentUpdatesEnabled
              ? l10n.configUpdateTechnicalOfficialFeedYes
              : l10n.configUpdateTechnicalOfficialFeedNo,
        ),
      ],
    );
  }

  List<SupportDiagnosticsSection> buildSections({
    required AppLocalizations l10n,
    required String currentAppVersion,
    UpdateCheckDiagnostics? manualDiagnostics,
    UpdateCheckDiagnostics? backgroundDiagnostics,
    UpdateCheckDiagnostics? automaticDiagnostics,
    bool? updateNotificationsEnabled,
    bool? automaticSilentUpdatesEnabled,
  }) {
    final sections = <SupportDiagnosticsSection>[];

    if (updateNotificationsEnabled != null && automaticSilentUpdatesEnabled != null) {
      sections.add(
        buildPreferencesSection(
          l10n: l10n,
          updateNotificationsEnabled: updateNotificationsEnabled,
          automaticSilentUpdatesEnabled: automaticSilentUpdatesEnabled,
        ),
      );
    }

    if (manualDiagnostics != null) {
      sections.add(
        _buildSection(
          l10n: l10n,
          title: l10n.configUpdateTechnicalTitle,
          currentAppVersion: currentAppVersion,
          diagnostics: manualDiagnostics,
        ),
      );
    }

    if (backgroundDiagnostics != null) {
      sections.add(
        _buildSection(
          l10n: l10n,
          title: l10n.configUpdateTechnicalBackgroundTitle,
          currentAppVersion: currentAppVersion,
          diagnostics: backgroundDiagnostics,
        ),
      );
    }

    if (automaticDiagnostics != null) {
      sections.add(
        _buildSection(
          l10n: l10n,
          title: l10n.configUpdateTechnicalAutomaticTitle,
          currentAppVersion: currentAppVersion,
          diagnostics: automaticDiagnostics,
        ),
      );
    }

    return sections;
  }

  SupportDiagnosticsSection _buildSection({
    required AppLocalizations l10n,
    required String title,
    required String currentAppVersion,
    required UpdateCheckDiagnostics diagnostics,
  }) {
    final fields = <SupportDiagnosticsField>[
      SupportDiagnosticsField(
        key: l10n.configUpdateTechnicalCurrentVersion,
        value: diagnostics.currentVersion ?? currentAppVersion,
      ),
      if (diagnostics.checkId != null)
        SupportDiagnosticsField(
          key: l10n.configUpdateTechnicalCheckId,
          value: diagnostics.checkId,
        ),
      SupportDiagnosticsField(
        key: l10n.configUpdateTechnicalCheckedAt,
        value: _formatLastUpdateCheck(diagnostics.checkedAt),
      ),
      SupportDiagnosticsField(
        key: l10n.configUpdateTechnicalConfiguredFeed,
        value: diagnostics.configuredFeedUrl,
      ),
      SupportDiagnosticsField(
        key: l10n.configUpdateTechnicalRequestedFeed,
        value: diagnostics.requestedFeedUrl,
      ),
      SupportDiagnosticsField(
        key: l10n.configUpdateTechnicalOfficialFeed,
        value: isOfficialAutoUpdateFeedUrl(diagnostics.configuredFeedUrl)
            ? l10n.configUpdateTechnicalOfficialFeedYes
            : l10n.configUpdateTechnicalOfficialFeedNo,
      ),
      SupportDiagnosticsField(
        key: l10n.configUpdateTechnicalProbeRequestUrl,
        value: diagnostics.probeRequestUrl ?? diagnostics.requestedFeedUrl,
      ),
      SupportDiagnosticsField(
        key: l10n.configUpdateTechnicalProbeSucceeded,
        value: diagnostics.probeSucceeded == null
            ? null
            : diagnostics.probeSucceeded!
            ? l10n.configUpdateTechnicalOfficialFeedYes
            : l10n.configUpdateTechnicalOfficialFeedNo,
      ),
      if (diagnostics.probeMatchesSparkle != null)
        SupportDiagnosticsField(
          key: l10n.configUpdateTechnicalProbeMatchesSparkle,
          value: diagnostics.probeMatchesSparkle!
              ? l10n.configUpdateTechnicalOfficialFeedYes
              : l10n.configUpdateTechnicalOfficialFeedNo,
        ),
      SupportDiagnosticsField(
        key: l10n.configUpdateTechnicalCompletionSource,
        value: formatCompletionSource(l10n, diagnostics.completionSource),
      ),
      SupportDiagnosticsField(
        key: l10n.configUpdateTechnicalTriggerDurationMs,
        value: _formatDurationMs(diagnostics.triggerStartedAt, diagnostics.triggerCompletedAt),
      ),
      SupportDiagnosticsField(
        key: l10n.configUpdateTechnicalTotalDurationMs,
        value: _formatDurationMs(diagnostics.checkedAt, diagnostics.completedAt),
      ),
    ];

    if (diagnostics.appcastProbeItemCount != null) {
      fields.add(
        SupportDiagnosticsField(
          key: l10n.configUpdateTechnicalFeedItemCount,
          value: diagnostics.appcastProbeItemCount,
        ),
      );
    }

    if (diagnostics.remoteVersion != null && diagnostics.remoteVersion!.isNotEmpty) {
      fields.add(
        SupportDiagnosticsField(
          key: l10n.configUpdateTechnicalRemoteVersion,
          value: diagnostics.remoteVersion,
        ),
      );
    } else if (diagnostics.appcastProbeVersion != null && diagnostics.appcastProbeVersion!.isNotEmpty) {
      fields.add(
        SupportDiagnosticsField(
          key: l10n.configUpdateTechnicalRemoteVersion,
          value: diagnostics.appcastProbeVersion,
        ),
      );
    }

    _addOptionalField(fields, l10n.configUpdateTechnicalAssetName, diagnostics.assetName);
    _addOptionalField(fields, l10n.configUpdateTechnicalAssetUrl, diagnostics.assetUrl);
    _addOptionalField(fields, l10n.configUpdateTechnicalAssetSize, diagnostics.assetSize);
    _addOptionalField(fields, l10n.configUpdateTechnicalSha256, diagnostics.sha256);
    _addOptionalField(fields, l10n.configUpdateTechnicalActualSha256, diagnostics.actualSha256);
    _addOptionalField(fields, l10n.configUpdateTechnicalHashValidationStatus, diagnostics.hashValidationStatus);
    _addOptionalField(fields, l10n.configUpdateTechnicalRolloutChannel, diagnostics.rolloutChannel);
    _addOptionalField(fields, l10n.configUpdateTechnicalRolloutPercentage, diagnostics.rolloutPercentage);
    _addOptionalField(fields, l10n.configUpdateTechnicalRolloutBucket, diagnostics.rolloutBucket);
    if (diagnostics.rolloutEligible != null) {
      fields.add(
        SupportDiagnosticsField(
          key: l10n.configUpdateTechnicalRolloutEligible,
          value: diagnostics.rolloutEligible!
              ? l10n.configUpdateTechnicalOfficialFeedYes
              : l10n.configUpdateTechnicalOfficialFeedNo,
        ),
      );
    }
    _addOptionalField(fields, l10n.configUpdateTechnicalPendingVersion, diagnostics.pendingVersion);
    _addOptionalField(fields, l10n.configUpdateTechnicalInstallerPath, diagnostics.installerPath);
    _addOptionalField(fields, l10n.configUpdateTechnicalInstallerLogPath, diagnostics.installerLogPath);
    _addOptionalField(fields, l10n.configUpdateTechnicalInstallDirectory, diagnostics.installDirectory);
    _addOptionalField(
      fields,
      l10n.configUpdateTechnicalUpdateDirectorySecurity,
      diagnostics.updateDirectorySecurityStatus,
    );
    if (diagnostics.installDirectoryWritable != null) {
      fields.add(
        SupportDiagnosticsField(
          key: l10n.configUpdateTechnicalInstallDirectoryWritable,
          value: diagnostics.installDirectoryWritable!
              ? l10n.configUpdateTechnicalOfficialFeedYes
              : l10n.configUpdateTechnicalOfficialFeedNo,
        ),
      );
    }
    _addOptionalField(fields, l10n.configUpdateTechnicalSilentStrategy, diagnostics.silentUpdateStrategy);
    _addOptionalField(fields, l10n.configUpdateTechnicalLauncherPath, diagnostics.launcherPath);
    _addOptionalField(fields, l10n.configUpdateTechnicalLauncherStatusPath, diagnostics.launcherStatusPath);
    _addOptionalField(fields, l10n.configUpdateTechnicalLauncherState, diagnostics.launcherState);
    _addOptionalField(fields, l10n.configUpdateTechnicalHelperSha256, diagnostics.helperSha256);
    _addOptionalField(fields, l10n.configUpdateTechnicalHelperSignatureStatus, diagnostics.helperSignatureStatus);
    _addOptionalField(fields, l10n.configUpdateTechnicalFeedSignatureStatus, diagnostics.feedSignatureStatus);
    if (diagnostics.feedSignatureRequired != null) {
      fields.add(
        SupportDiagnosticsField(
          key: l10n.configUpdateTechnicalFeedSignatureRequired,
          value: diagnostics.feedSignatureRequired!
              ? l10n.configUpdateTechnicalOfficialFeedYes
              : l10n.configUpdateTechnicalOfficialFeedNo,
        ),
      );
    }
    _addOptionalField(fields, l10n.configUpdateTechnicalAppPid, diagnostics.appPid);
    _addOptionalField(fields, l10n.configUpdateTechnicalSignatureStatus, diagnostics.signatureStatus);
    if (diagnostics.signatureRequired != null) {
      fields.add(
        SupportDiagnosticsField(
          key: l10n.configUpdateTechnicalSignatureRequired,
          value: diagnostics.signatureRequired!
              ? l10n.configUpdateTechnicalOfficialFeedYes
              : l10n.configUpdateTechnicalOfficialFeedNo,
        ),
      );
    }
    _addOptionalField(
      fields,
      l10n.configUpdateTechnicalWaitForAppExitDurationMs,
      diagnostics.waitForAppExitDurationMs,
    );
    _addOptionalField(fields, l10n.configUpdateTechnicalNonAdminExitCode, diagnostics.nonAdminExitCode);
    _addOptionalField(fields, l10n.configUpdateTechnicalNonAdminDurationMs, diagnostics.nonAdminDurationMs);
    _addOptionalField(fields, l10n.configUpdateTechnicalElevatedExitCode, diagnostics.elevatedExitCode);
    _addOptionalField(fields, l10n.configUpdateTechnicalElevatedDurationMs, diagnostics.elevatedDurationMs);
    if (diagnostics.elevatedRetryStarted != null) {
      fields.add(
        SupportDiagnosticsField(
          key: l10n.configUpdateTechnicalElevatedRetryStarted,
          value: diagnostics.elevatedRetryStarted!
              ? l10n.configUpdateTechnicalOfficialFeedYes
              : l10n.configUpdateTechnicalOfficialFeedNo,
        ),
      );
    }
    if (diagnostics.elevatedCancelled != null) {
      fields.add(
        SupportDiagnosticsField(
          key: l10n.configUpdateTechnicalElevatedCancelled,
          value: diagnostics.elevatedCancelled!
              ? l10n.configUpdateTechnicalOfficialFeedYes
              : l10n.configUpdateTechnicalOfficialFeedNo,
        ),
      );
    }
    _addOptionalField(fields, l10n.configUpdateTechnicalAutomaticFailureCount, diagnostics.automaticFailureCount);
    if (diagnostics.automaticCooldownUntil != null) {
      fields.add(
        SupportDiagnosticsField(
          key: l10n.configUpdateTechnicalAutomaticCooldownUntil,
          value: _formatLastUpdateCheck(diagnostics.automaticCooldownUntil!),
        ),
      );
    }

    _addOptionalField(
      fields,
      diagnostics.errorMessage != null && diagnostics.errorMessage!.isNotEmpty
          ? l10n.configUpdateTechnicalUpdaterError
          : l10n.configUpdateTechnicalAppcastError,
      diagnostics.errorMessage != null && diagnostics.errorMessage!.isNotEmpty
          ? diagnostics.errorMessage
          : diagnostics.probeErrorMessage,
    );

    return SupportDiagnosticsSection(
      title: title,
      fields: fields,
    );
  }

  void _addOptionalField(
    List<SupportDiagnosticsField> fields,
    String key,
    Object? value,
  ) {
    if (value == null) {
      return;
    }

    if (value is String && value.isEmpty) {
      return;
    }

    fields.add(
      SupportDiagnosticsField(
        key: key,
        value: value,
      ),
    );
  }

  String _formatLastUpdateCheck(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _formatDurationMs(DateTime? startedAt, DateTime? completedAt) {
    if (startedAt == null || completedAt == null) {
      return '-';
    }
    return completedAt.difference(startedAt).inMilliseconds.toString();
  }

  /// Proactive status line for the last automatic silent-update attempt in
  /// Settings. Suppresses completion suffixes when the operator opted out of
  /// update notifications so failures are not surfaced as unsolicited warnings.
  /// Full diagnostics remain available via copy/manual check flows.
  static String buildAutomaticUpdateStatusLabel({
    required AppLocalizations l10n,
    required UpdateCheckDiagnostics? diagnostics,
    required bool updateNotificationsEnabled,
    required bool automaticSilentUpdatesEnabled,
    required String Function(DateTime dateTime) formatCheckedAt,
  }) {
    final isManualOnlyMode = AppPreferencesPolicy.isManualOnlyUpdateMode(
      updateNotificationsEnabled: updateNotificationsEnabled,
      automaticSilentUpdatesEnabled: automaticSilentUpdatesEnabled,
    );
    if (isManualOnlyMode || diagnostics == null) {
      return '${l10n.configLastAutomaticUpdatePrefix}${l10n.configLastUpdateNever}';
    }

    final checkedAt = formatCheckedAt(diagnostics.checkedAt);
    if (!updateNotificationsEnabled) {
      return '${l10n.configLastAutomaticUpdatePrefix}$checkedAt';
    }

    final completion = diagnostics.completionSource == null
        ? ''
        : ' - ${formatCompletionSource(l10n, diagnostics.completionSource)}';
    return '${l10n.configLastAutomaticUpdatePrefix}$checkedAt$completion';
  }

  /// Proactive status line for the last WinSparkle background check in
  /// Settings. Follows the same notification-preference suppression rules as
  /// [buildAutomaticUpdateStatusLabel].
  static String buildBackgroundUpdateStatusLabel({
    required AppLocalizations l10n,
    required UpdateCheckDiagnostics? diagnostics,
    required bool updateNotificationsEnabled,
    required bool automaticSilentUpdatesEnabled,
    required String Function(DateTime dateTime) formatCheckedAt,
  }) {
    final isManualOnlyMode = AppPreferencesPolicy.isManualOnlyUpdateMode(
      updateNotificationsEnabled: updateNotificationsEnabled,
      automaticSilentUpdatesEnabled: automaticSilentUpdatesEnabled,
    );
    if (isManualOnlyMode || diagnostics == null) {
      return '';
    }

    final checkedAt = formatCheckedAt(diagnostics.checkedAt);
    if (!updateNotificationsEnabled) {
      return '${l10n.configLastBackgroundUpdatePrefix}$checkedAt';
    }

    final completion = diagnostics.completionSource == null
        ? ''
        : ' - ${formatCompletionSource(l10n, diagnostics.completionSource)}';
    return '${l10n.configLastBackgroundUpdatePrefix}$checkedAt$completion';
  }

  /// Formats a [UpdateCheckCompletionSource] to a localized display string.
  ///
  /// Exposed as `static` so callers (e.g. `ConfigPage`) can reuse it without
  /// duplicating the switch.
  static String formatCompletionSource(
    AppLocalizations l10n,
    UpdateCheckCompletionSource? source,
  ) {
    return switch (source) {
      UpdateCheckCompletionSource.updateAvailable => l10n.configUpdateCompletionSourceUpdateAvailable,
      UpdateCheckCompletionSource.updateNotAvailable => l10n.configUpdateCompletionSourceUpdateNotAvailable,
      UpdateCheckCompletionSource.updaterError => l10n.configUpdateCompletionSourceUpdaterError,
      UpdateCheckCompletionSource.triggerTimeout => l10n.configUpdateCompletionSourceTriggerTimeout,
      UpdateCheckCompletionSource.completionTimeout => l10n.configUpdateCompletionSourceCompletionTimeout,
      UpdateCheckCompletionSource.triggerFailure => l10n.configUpdateCompletionSourceTriggerFailure,
      UpdateCheckCompletionSource.notInitialized => l10n.configUpdateCompletionSourceNotInitialized,
      UpdateCheckCompletionSource.circuitOpen => l10n.configUpdateCompletionSourceCircuitOpen,
      UpdateCheckCompletionSource.automaticDisabled => l10n.configUpdateCompletionSourceAutomaticDisabled,
      UpdateCheckCompletionSource.automaticPendingCompleted =>
        l10n.configUpdateCompletionSourceAutomaticPendingCompleted,
      UpdateCheckCompletionSource.automaticPendingFailed => l10n.configUpdateCompletionSourceAutomaticPendingFailed,
      UpdateCheckCompletionSource.automaticUpdateNotAvailable =>
        l10n.configUpdateCompletionSourceAutomaticUpdateNotAvailable,
      UpdateCheckCompletionSource.automaticValidationFailure =>
        l10n.configUpdateCompletionSourceAutomaticValidationFailure,
      UpdateCheckCompletionSource.automaticDownloadFailure => l10n.configUpdateCompletionSourceAutomaticDownloadFailure,
      UpdateCheckCompletionSource.automaticInstallReady => l10n.configUpdateCompletionSourceAutomaticInstallReady,
      UpdateCheckCompletionSource.automaticAwaitingUserConsent =>
        l10n.configUpdateCompletionSourceAutomaticAwaitingUserConsent,
      UpdateCheckCompletionSource.automaticInstallStarted => l10n.configUpdateCompletionSourceAutomaticInstallStarted,
      UpdateCheckCompletionSource.automaticInstallFailure => l10n.configUpdateCompletionSourceAutomaticInstallFailure,
      UpdateCheckCompletionSource.automaticCooldown => l10n.configUpdateCompletionSourceAutomaticCooldown,
      UpdateCheckCompletionSource.automaticRolloutSkipped => l10n.configUpdateCompletionSourceAutomaticRolloutSkipped,
      UpdateCheckCompletionSource.automaticCancelled => l10n.configUpdateCompletionSourceAutomaticCancelled,
      UpdateCheckCompletionSource.automaticQuietHours => l10n.configUpdateCompletionSourceAutomaticQuietHours,
      null => '-',
    };
  }
}
