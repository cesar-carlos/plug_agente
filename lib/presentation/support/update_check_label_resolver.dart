import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/support/update_support_diagnostics_builder.dart';

class UpdateCheckLabelResolver {
  const UpdateCheckLabelResolver();

  static String formatCheckedAt(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String lastUpdateCheckLabel({
    required AppLocalizations l10n,
    required String manualCheckDisplayLabel,
    required UpdateCheckDiagnostics? lastManualDiagnostics,
    required UpdateCheckDiagnostics? lastBackgroundDiagnostics,
  }) {
    if (manualCheckDisplayLabel.isNotEmpty) {
      return manualCheckDisplayLabel;
    }

    final latest = _latestCheckDiagnostics(
      manual: lastManualDiagnostics,
      background: lastBackgroundDiagnostics,
    );
    if (latest == null) {
      return '';
    }

    return '${l10n.configLastUpdatePrefix}${formatCheckedAt(latest.checkedAt)}';
  }

  String lastBackgroundUpdateLabel({
    required AppLocalizations l10n,
    required IAutoUpdateOrchestrator orchestrator,
  }) {
    if (orchestrator.automaticSilentUpdatesEnabled) {
      return '';
    }

    return UpdateSupportDiagnosticsBuilder.buildBackgroundUpdateStatusLabel(
      l10n: l10n,
      diagnostics: orchestrator.lastBackgroundDiagnostics,
      updateNotificationsEnabled: orchestrator.updateNotificationsEnabled,
      automaticSilentUpdatesEnabled: orchestrator.automaticSilentUpdatesEnabled,
      formatCheckedAt: formatCheckedAt,
    );
  }

  String lastAutomaticUpdateLabel({
    required AppLocalizations l10n,
    required IAutoUpdateOrchestrator orchestrator,
  }) {
    return UpdateSupportDiagnosticsBuilder.buildAutomaticUpdateStatusLabel(
      l10n: l10n,
      diagnostics: orchestrator.lastAutomaticDiagnostics,
      updateNotificationsEnabled: orchestrator.updateNotificationsEnabled,
      automaticSilentUpdatesEnabled: orchestrator.automaticSilentUpdatesEnabled,
      formatCheckedAt: formatCheckedAt,
    );
  }

  String autoUpdateFeedStatusLabel(AppLocalizations l10n) {
    final feedUrl = resolveAutoUpdateFeedUrl(environment: AppEnvironment.snapshot());
    if (isOfficialAutoUpdateFeedUrl(feedUrl)) {
      return l10n.configAutoUpdateFeedOfficial;
    }
    return l10n.configAutoUpdateFeedCustom;
  }

  String? pendingUpdateNotice({
    required AppLocalizations l10n,
    required IAutoUpdateOrchestrator orchestrator,
    required bool hasPendingDownloadedUpdate,
  }) {
    if (orchestrator.updateNotificationsEnabled) {
      return null;
    }
    if (hasPendingDownloadedUpdate) {
      return l10n.configUpdatePendingReadyNotice;
    }
    if (orchestrator.hasUpdateAwaitingUserConsent) {
      return l10n.configUpdatePendingAwaitingConsentNotice;
    }
    return null;
  }

  String? autoUpdateUnavailableMessage({
    required AppLocalizations l10n,
    required bool isAutoUpdateAvailable,
    RuntimeCapabilities? capabilities,
  }) {
    if (isAutoUpdateAvailable) {
      return null;
    }
    return _resolveUpdateUnavailableMessage(l10n, capabilities);
  }

  UpdateCheckDiagnostics? _latestCheckDiagnostics({
    required UpdateCheckDiagnostics? manual,
    required UpdateCheckDiagnostics? background,
  }) {
    if (background == null || (manual != null && manual.checkedAt.isAfter(background.checkedAt))) {
      return manual;
    }
    return background;
  }

  String _resolveUpdateUnavailableMessage(
    AppLocalizations l10n,
    RuntimeCapabilities? capabilities,
  ) {
    if (capabilities != null && !capabilities.supportsAutoUpdate) {
      return l10n.configAutoUpdateNotSupported;
    }

    if (hasInvalidAutoUpdateFeedOverride(environment: AppEnvironment.snapshot())) {
      return '${l10n.configAutoUpdateNotConfigured}\n${l10n.configAutoUpdateOfficialFeedExpected(officialAutoUpdateFeedUrl)}';
    }

    return l10n.configAutoUpdateNotSupported;
  }
}
