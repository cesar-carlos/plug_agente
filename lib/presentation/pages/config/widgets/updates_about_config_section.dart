import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/models/update_check_inline_notice.dart';
import 'package:plug_agente/presentation/pages/config/widgets/update_check_inline_notice_bar.dart';
import 'package:plug_agente/shared/widgets/common/feedback/inline_feedback_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';

class UpdatesAboutConfigSection extends StatelessWidget {
  const UpdatesAboutConfigSection({
    required this.appVersion,
    required this.lastUpdateCheck,
    required this.lastBackgroundUpdateCheck,
    required this.lastAutomaticUpdateCheck,
    required this.autoUpdateFeedStatus,
    required this.updateNotificationsEnabled,
    required this.automaticSilentUpdatesEnabled,
    required this.onCheckUpdates,
    required this.onCheckAutomaticUpdates,
    required this.onCopyUpdateDiagnostics,
    required this.onUpdateNotificationsChanged,
    required this.onAutomaticSilentUpdatesChanged,
    required this.onUseManualOnlyUpdateMode,
    this.isAutoUpdateAvailable = true,
    this.unavailableMessage,
    this.isCheckingUpdates = false,
    this.isCheckingAutomaticUpdates = false,
    this.pendingUpdateNotice,
    this.releaseNotes,
    this.releaseNotesUrl,
    this.updateCheckNotice,
    super.key,
  });

  final String appVersion;
  final String lastUpdateCheck;
  final String lastBackgroundUpdateCheck;
  final String lastAutomaticUpdateCheck;
  final String autoUpdateFeedStatus;
  final bool updateNotificationsEnabled;
  final bool automaticSilentUpdatesEnabled;
  final VoidCallback onCheckUpdates;
  final VoidCallback onCheckAutomaticUpdates;
  final VoidCallback onCopyUpdateDiagnostics;
  final ValueChanged<bool> onUpdateNotificationsChanged;
  final ValueChanged<bool> onAutomaticSilentUpdatesChanged;
  final VoidCallback onUseManualOnlyUpdateMode;
  final bool isAutoUpdateAvailable;
  final String? unavailableMessage;
  final bool isCheckingUpdates;
  final bool isCheckingAutomaticUpdates;

  /// Shown when an update is staged or awaiting consent but proactive
  /// notifications are disabled.
  final String? pendingUpdateNotice;

  /// Plain-text release notes from the appcast item description. When set,
  /// renders as a Fluent expander below the update status. Empty/null hides
  /// the expander entirely.
  final String? releaseNotes;

  /// External "release notes link" from `sparkle:releaseNotesLink`. Shown
  /// as a `Open in browser` link inside the expander when present.
  final String? releaseNotesUrl;
  final UpdateCheckInlineNotice? updateCheckNotice;

  bool get _isManualOnlyMode => !updateNotificationsEnabled && !automaticSilentUpdatesEnabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final displayLastUpdate = lastUpdateCheck.isEmpty ? l10n.configLastUpdateNever : lastUpdateCheck;
    final displayLastAutomaticUpdate = lastAutomaticUpdateCheck.trim().isEmpty
        ? '${l10n.configLastAutomaticUpdatePrefix}${l10n.configLastUpdateNever}'
        : lastAutomaticUpdateCheck;
    final hasBackgroundUpdate = lastBackgroundUpdateCheck.trim().isNotEmpty;
    final pendingNotice = pendingUpdateNotice?.trim();
    return SingleChildScrollView(
      child: SettingsSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSectionTitle(title: l10n.gsSectionUpdates),
            const SizedBox(height: AppSpacing.md),
            if (isAutoUpdateAvailable)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.configManualCheckSectionTitle,
                    style: context.bodyStrong,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    displayLastUpdate,
                    key: const ValueKey('updates_last_check_label'),
                    style: context.captionText,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (updateCheckNotice != null) ...[
                    UpdateCheckInlineNoticeBar(notice: updateCheckNotice!),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Row(
                    children: [
                      Button(
                        key: const ValueKey('updates_check_now_button'),
                        onPressed: isCheckingUpdates ? null : onCheckUpdates,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isCheckingUpdates)
                              const SizedBox(
                                key: ValueKey('updates_progress_ring'),
                                width: 16,
                                height: 16,
                                child: ProgressRing(strokeWidth: 2),
                              )
                            else
                              const Icon(FluentIcons.refresh),
                            const SizedBox(width: AppSpacing.xs),
                            Text(l10n.configCheckUpdatesNow),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (hasBackgroundUpdate) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      lastBackgroundUpdateCheck,
                      style: context.captionText,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    displayLastAutomaticUpdate,
                    key: const ValueKey('automatic_updates_last_attempt_label'),
                    style: context.captionText,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    autoUpdateFeedStatus,
                    key: const ValueKey('automatic_updates_feed_status_label'),
                    style: context.captionText,
                  ),
                  if ((releaseNotes ?? '').trim().isNotEmpty || (releaseNotesUrl ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _ReleaseNotesExpander(
                      key: const ValueKey('updates_release_notes_expander'),
                      headerLabel: l10n.configAutoUpdateReleaseNotesHeader,
                      linkLabel: l10n.configAutoUpdateReleaseNotesLink,
                      notes: releaseNotes,
                      url: releaseNotesUrl,
                    ),
                  ],
                  if (pendingNotice != null && pendingNotice.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    InlineFeedbackCard(
                      key: const ValueKey('updates_pending_notice'),
                      severity: InfoBarSeverity.warning,
                      message: pendingNotice,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  if (!_isManualOnlyMode) ...[
                    HyperlinkButton(
                      key: const ValueKey('updates_manual_only_mode_link'),
                      onPressed: onUseManualOnlyUpdateMode,
                      child: Text(l10n.configUseManualOnlyUpdatesLink),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  SettingsToggleTile(
                    key: const ValueKey('update_notifications_toggle'),
                    label: l10n.configUpdateNotificationsToggle,
                    description: l10n.configUpdateNotificationsDescription,
                    value: updateNotificationsEnabled,
                    onChanged: onUpdateNotificationsChanged,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SettingsToggleTile(
                    key: const ValueKey('automatic_silent_updates_toggle'),
                    label: l10n.configAutomaticSilentUpdatesToggle,
                    description: l10n.configAutomaticSilentUpdatesDescription,
                    value: automaticSilentUpdatesEnabled,
                    onChanged: onAutomaticSilentUpdatesChanged,
                  ),
                  if (automaticSilentUpdatesEnabled) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Button(
                      key: const ValueKey('automatic_updates_check_now_button'),
                      onPressed: isCheckingAutomaticUpdates ? null : onCheckAutomaticUpdates,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCheckingAutomaticUpdates)
                            const SizedBox(
                              key: ValueKey('automatic_updates_progress_ring'),
                              width: 16,
                              height: 16,
                              child: ProgressRing(strokeWidth: 2),
                            )
                          else
                            const Icon(FluentIcons.refresh),
                          const SizedBox(width: AppSpacing.xs),
                          Text(l10n.configAutomaticSilentUpdatesCheckNow),
                        ],
                      ),
                    ),
                  ],
                ],
              )
            else
              Text(
                unavailableMessage ?? l10n.configAutoUpdateNotSupported,
                style: context.captionText,
              ),
            const SizedBox(height: AppSpacing.md),
            Button(
              key: const ValueKey('updates_copy_diagnostics_button'),
              onPressed: onCopyUpdateDiagnostics,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.copy),
                  const SizedBox(width: AppSpacing.xs),
                  Text(l10n.configCopyUpdateDiagnostics),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.lg),
            SettingsSectionTitle(title: l10n.gsSectionAbout),
            const SizedBox(height: AppSpacing.md),
            SettingsKeyValue(
              label: l10n.gsLabelVersion,
              value: appVersion,
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsKeyValue(
              label: l10n.gsLabelLicense,
              value: l10n.gsLicenseMit,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseNotesExpander extends StatelessWidget {
  const _ReleaseNotesExpander({
    required this.headerLabel,
    required this.linkLabel,
    this.notes,
    this.url,
    super.key,
  });

  final String headerLabel;
  final String linkLabel;
  final String? notes;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final trimmedNotes = (notes ?? '').trim();
    final trimmedUrl = (url ?? '').trim();
    return Expander(
      header: Text(headerLabel),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trimmedNotes.isNotEmpty)
            SelectableText(
              trimmedNotes,
              style: context.bodyText,
            ),
          if (trimmedNotes.isNotEmpty && trimmedUrl.isNotEmpty) const SizedBox(height: AppSpacing.sm),
          if (trimmedUrl.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$linkLabel: ', style: context.captionText),
                Flexible(
                  child: SelectableText(
                    trimmedUrl,
                    key: const ValueKey('updates_release_notes_link'),
                    style: context.captionText,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
