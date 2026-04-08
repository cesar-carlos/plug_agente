import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';

class GeneralConfigSection extends StatelessWidget {
  const GeneralConfigSection({
    required this.isDarkThemeEnabled,
    required this.startWithWindows,
    required this.startMinimized,
    required this.minimizeToTray,
    required this.closeToTray,
    required this.lastUpdateCheck,
    required this.onDarkThemeChanged,
    required this.onStartWithWindowsChanged,
    required this.onStartMinimizedChanged,
    required this.onMinimizeToTrayChanged,
    required this.onCloseToTrayChanged,
    required this.onCheckUpdates,
    required this.onOpenStartupSettings,
    required this.appVersion,
    this.startupSupported = true,
    this.startupError,
    this.supportsAutoUpdate = true,
    super.key,
  });

  final bool isDarkThemeEnabled;
  final bool startWithWindows;
  final bool startMinimized;
  final bool minimizeToTray;
  final bool closeToTray;
  final String lastUpdateCheck;
  final ValueChanged<bool> onDarkThemeChanged;
  final ValueChanged<bool> onStartWithWindowsChanged;
  final ValueChanged<bool> onStartMinimizedChanged;
  final ValueChanged<bool> onMinimizeToTrayChanged;
  final ValueChanged<bool> onCloseToTrayChanged;
  final VoidCallback onCheckUpdates;
  final VoidCallback onOpenStartupSettings;
  final String appVersion;
  final bool startupSupported;
  final String? startupError;
  final bool supportsAutoUpdate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final displayLastUpdate = lastUpdateCheck.isEmpty ? l10n.configLastUpdateNever : lastUpdateCheck;
    return SingleChildScrollView(
      child: SettingsSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSectionTitle(title: l10n.gsSectionAppearance),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: l10n.gsToggleDarkTheme,
              value: isDarkThemeEnabled,
              onChanged: onDarkThemeChanged,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.lg),
            SettingsSectionTitle(title: l10n.gsSectionSystem),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: l10n.gsToggleStartWithWindows,
              value: startWithWindows,
              onChanged: startupSupported ? onStartWithWindowsChanged : null,
            ),
            if (startupError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _StartupErrorMessage(
                error: startupError!,
                onOpenSettings: onOpenStartupSettings,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: l10n.gsToggleStartMinimized,
              value: startMinimized,
              onChanged: onStartMinimizedChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: l10n.gsToggleMinimizeToTray,
              value: minimizeToTray,
              onChanged: onMinimizeToTrayChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: l10n.gsToggleCloseToTray,
              value: closeToTray,
              onChanged: onCloseToTrayChanged,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.lg),
            SettingsSectionTitle(title: l10n.gsSectionUpdates),
            const SizedBox(height: AppSpacing.md),
            if (supportsAutoUpdate)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${l10n.gsCheckUpdatesWithDate}\n$displayLastUpdate',
                      style: context.bodyText,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(FluentIcons.refresh),
                    onPressed: onCheckUpdates,
                  ),
                ],
              )
            else
              Text(
                l10n.configAutoUpdateNotSupported,
                style: context.captionText,
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

class _StartupErrorMessage extends StatelessWidget {
  const _StartupErrorMessage({
    required this.error,
    required this.onOpenSettings,
  });

  final String error;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final feedbackColors = context.appColors.feedback(AppFeedbackTone.error);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: feedbackColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: feedbackColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_badge,
            color: feedbackColors.accent,
            size: 16,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              error,
              style: context.captionText.copyWith(
                color: feedbackColors.accent,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppButton(
            label: l10n.gsButtonOpenSettings,
            filledBackgroundColor: feedbackColors.background,
            filledForegroundColor: feedbackColors.accent,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}
