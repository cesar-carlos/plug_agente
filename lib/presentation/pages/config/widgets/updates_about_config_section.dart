import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';

class UpdatesAboutConfigSection extends StatelessWidget {
  const UpdatesAboutConfigSection({
    required this.appVersion,
    required this.lastUpdateCheck,
    required this.lastBackgroundUpdateCheck,
    required this.lastAutomaticUpdateCheck,
    required this.automaticSilentUpdatesEnabled,
    required this.onCheckUpdates,
    required this.onCopyUpdateDiagnostics,
    required this.onAutomaticSilentUpdatesChanged,
    this.isAutoUpdateAvailable = true,
    this.unavailableMessage,
    this.isCheckingUpdates = false,
    super.key,
  });

  final String appVersion;
  final String lastUpdateCheck;
  final String lastBackgroundUpdateCheck;
  final String lastAutomaticUpdateCheck;
  final bool automaticSilentUpdatesEnabled;
  final VoidCallback onCheckUpdates;
  final VoidCallback onCopyUpdateDiagnostics;
  final ValueChanged<bool> onAutomaticSilentUpdatesChanged;
  final bool isAutoUpdateAvailable;
  final String? unavailableMessage;
  final bool isCheckingUpdates;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final displayLastUpdate = lastUpdateCheck.isEmpty ? l10n.configLastUpdateNever : lastUpdateCheck;
    final hasBackgroundUpdate = lastBackgroundUpdateCheck.trim().isNotEmpty;
    final hasAutomaticUpdate = lastAutomaticUpdateCheck.trim().isNotEmpty;
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${l10n.gsCheckUpdatesWithDate}\n$displayLastUpdate',
                          style: context.bodyText,
                        ),
                      ),
                      if (isCheckingUpdates)
                        const SizedBox(
                          key: ValueKey('updates_progress_ring'),
                          width: 20,
                          height: 20,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          key: const ValueKey('updates_refresh_button'),
                          icon: const Icon(FluentIcons.refresh),
                          onPressed: onCheckUpdates,
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
                  if (hasAutomaticUpdate) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      lastAutomaticUpdateCheck,
                      style: context.captionText,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  SettingsToggleTile(
                    key: const ValueKey('automatic_silent_updates_toggle'),
                    label: l10n.configAutomaticSilentUpdatesToggle,
                    description: l10n.configAutomaticSilentUpdatesDescription,
                    value: automaticSilentUpdatesEnabled,
                    onChanged: onAutomaticSilentUpdatesChanged,
                  ),
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
