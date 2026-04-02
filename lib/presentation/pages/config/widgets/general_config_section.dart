import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/theme/theme.dart';
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
    return SingleChildScrollView(
      child: SettingsSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsSectionTitle(title: AppStrings.gsSectionAppearance),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: AppStrings.gsToggleDarkTheme,
              value: isDarkThemeEnabled,
              onChanged: onDarkThemeChanged,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.lg),
            const SettingsSectionTitle(title: AppStrings.gsSectionSystem),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: AppStrings.gsToggleStartWithWindows,
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
              label: AppStrings.gsToggleStartMinimized,
              value: startMinimized,
              onChanged: onStartMinimizedChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: AppStrings.gsToggleMinimizeToTray,
              value: minimizeToTray,
              onChanged: onMinimizeToTrayChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: AppStrings.gsToggleCloseToTray,
              value: closeToTray,
              onChanged: onCloseToTrayChanged,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.lg),
            const SettingsSectionTitle(title: AppStrings.gsSectionUpdates),
            const SizedBox(height: AppSpacing.md),
            if (supportsAutoUpdate)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${AppStrings.gsCheckUpdatesWithDate}\n$lastUpdateCheck',
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
                AppStrings.gsAutoUpdateNotSupported,
                style: context.captionText,
              ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.lg),
            const SettingsSectionTitle(title: AppStrings.gsSectionAbout),
            const SizedBox(height: AppSpacing.md),
            SettingsKeyValue(
              label: AppStrings.gsLabelVersion,
              value: appVersion,
            ),
            const SizedBox(height: AppSpacing.md),
            const SettingsKeyValue(
              label: AppStrings.gsLabelLicense,
              value: AppStrings.gsLicenseMit,
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
          FilledButton(
            onPressed: onOpenSettings,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(
                feedbackColors.background,
              ),
              foregroundColor: WidgetStateProperty.all(feedbackColors.accent),
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
            ),
            child: const Text(AppStrings.gsButtonOpenSettings),
          ),
        ],
      ),
    );
  }
}
