import 'package:flutter/foundation.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/models/update_check_inline_notice.dart';
import 'package:plug_agente/presentation/providers/updates_settings_provider.dart';

@immutable
class UpdatesConfigViewState {
  const UpdatesConfigViewState({
    required this.appVersion,
    required this.lastUpdateCheck,
    required this.lastBackgroundUpdateCheck,
    required this.lastAutomaticUpdateCheck,
    required this.autoUpdateFeedStatus,
    required this.updateNotificationsEnabled,
    required this.automaticSilentUpdatesEnabled,
    required this.isCheckingUpdates,
    required this.isCheckingAutomaticUpdates,
    required this.isAutoUpdateAvailable,
    required this.autoUpdateUnavailableMessage,
    required this.pendingUpdateNotice,
    required this.releaseNotes,
    required this.releaseNotesUrl,
    required this.updateCheckNotice,
  });

  factory UpdatesConfigViewState.fromProvider(
    UpdatesSettingsProvider provider,
    AppLocalizations l10n,
  ) {
    return UpdatesConfigViewState(
      appVersion: provider.appVersion,
      lastUpdateCheck: provider.lastUpdateCheckLabel(l10n),
      lastBackgroundUpdateCheck: provider.lastBackgroundUpdateLabel(l10n),
      lastAutomaticUpdateCheck: provider.lastAutomaticUpdateLabel(l10n),
      autoUpdateFeedStatus: provider.autoUpdateFeedStatusLabel(l10n),
      updateNotificationsEnabled: provider.updateNotificationsEnabled,
      automaticSilentUpdatesEnabled: provider.automaticSilentUpdatesEnabled,
      isCheckingUpdates: provider.isCheckingUpdates,
      isCheckingAutomaticUpdates: provider.isCheckingAutomaticUpdates,
      isAutoUpdateAvailable: provider.isAutoUpdateAvailable,
      autoUpdateUnavailableMessage: provider.autoUpdateUnavailableMessage(l10n),
      pendingUpdateNotice: provider.pendingUpdateNotice(l10n),
      releaseNotes: provider.releaseNotes,
      releaseNotesUrl: provider.releaseNotesUrl,
      updateCheckNotice: provider.updateCheckInlineNotice,
    );
  }

  final String appVersion;
  final String lastUpdateCheck;
  final String lastBackgroundUpdateCheck;
  final String lastAutomaticUpdateCheck;
  final String autoUpdateFeedStatus;
  final bool updateNotificationsEnabled;
  final bool automaticSilentUpdatesEnabled;
  final bool isCheckingUpdates;
  final bool isCheckingAutomaticUpdates;
  final bool isAutoUpdateAvailable;
  final String? autoUpdateUnavailableMessage;
  final String? pendingUpdateNotice;
  final String? releaseNotes;
  final String? releaseNotesUrl;
  final UpdateCheckInlineNotice? updateCheckNotice;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is UpdatesConfigViewState &&
            appVersion == other.appVersion &&
            lastUpdateCheck == other.lastUpdateCheck &&
            lastBackgroundUpdateCheck == other.lastBackgroundUpdateCheck &&
            lastAutomaticUpdateCheck == other.lastAutomaticUpdateCheck &&
            autoUpdateFeedStatus == other.autoUpdateFeedStatus &&
            updateNotificationsEnabled == other.updateNotificationsEnabled &&
            automaticSilentUpdatesEnabled == other.automaticSilentUpdatesEnabled &&
            isCheckingUpdates == other.isCheckingUpdates &&
            isCheckingAutomaticUpdates == other.isCheckingAutomaticUpdates &&
            isAutoUpdateAvailable == other.isAutoUpdateAvailable &&
            autoUpdateUnavailableMessage == other.autoUpdateUnavailableMessage &&
            pendingUpdateNotice == other.pendingUpdateNotice &&
            releaseNotes == other.releaseNotes &&
            releaseNotesUrl == other.releaseNotesUrl &&
            _inlineNoticeEquals(updateCheckNotice, other.updateCheckNotice);
  }

  @override
  int get hashCode => Object.hash(
    appVersion,
    lastUpdateCheck,
    lastBackgroundUpdateCheck,
    lastAutomaticUpdateCheck,
    autoUpdateFeedStatus,
    updateNotificationsEnabled,
    automaticSilentUpdatesEnabled,
    isCheckingUpdates,
    isCheckingAutomaticUpdates,
    isAutoUpdateAvailable,
    autoUpdateUnavailableMessage,
    pendingUpdateNotice,
    releaseNotes,
    releaseNotesUrl,
    _inlineNoticeHash(updateCheckNotice),
  );

  static bool _inlineNoticeEquals(
    UpdateCheckInlineNotice? a,
    UpdateCheckInlineNotice? b,
  ) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null) {
      return a == b;
    }
    return a.message == b.message &&
        a.hint == b.hint &&
        a.severity == b.severity &&
        a.diagnosticSections.length == b.diagnosticSections.length;
  }

  static int _inlineNoticeHash(UpdateCheckInlineNotice? notice) {
    if (notice == null) {
      return 0;
    }
    return Object.hash(
      notice.message,
      notice.hint,
      notice.severity,
      notice.diagnosticSections.length,
    );
  }
}
