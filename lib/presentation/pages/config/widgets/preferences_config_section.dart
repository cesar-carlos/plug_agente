import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/system_settings_error.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/layout/settings_components.dart';

class PreferencesConfigSection extends StatelessWidget {
  const PreferencesConfigSection({
    required this.isDarkThemeEnabled,
    required this.startWithWindows,
    required this.startMinimized,
    required this.minimizeToTray,
    required this.closeToTray,
    required this.onDarkThemeChanged,
    required this.onStartWithWindowsChanged,
    required this.onStartMinimizedChanged,
    required this.onMinimizeToTrayChanged,
    required this.onCloseToTrayChanged,
    required this.onOpenStartupSettings,
    this.startupSupported = true,
    this.startupError,
    super.key,
  });

  final bool isDarkThemeEnabled;
  final bool startWithWindows;
  final bool startMinimized;
  final bool minimizeToTray;
  final bool closeToTray;
  final ValueChanged<bool> onDarkThemeChanged;
  final ValueChanged<bool> onStartWithWindowsChanged;
  final ValueChanged<bool> onStartMinimizedChanged;
  final ValueChanged<bool> onMinimizeToTrayChanged;
  final ValueChanged<bool> onCloseToTrayChanged;
  final VoidCallback onOpenStartupSettings;
  final bool startupSupported;
  final SystemSettingsErrorState? startupError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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

  final SystemSettingsErrorState error;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final feedbackColors = context.appColors.feedback(AppFeedbackTone.error);
    final translated = _translate(l10n, error);

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
              translated,
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

String _translate(AppLocalizations l10n, SystemSettingsErrorState error) {
  final base = switch (error.code) {
    SystemSettingsErrorCode.startupToggleFailed => l10n.gsErrorStartupToggleFailed,
    SystemSettingsErrorCode.startupServiceUnavailable => l10n.gsErrorStartupServiceUnavailable,
    SystemSettingsErrorCode.startupOpenSystemSettingsFailed => l10n.gsErrorStartupOpenSystemSettingsFailed,
  };
  final detail = error.detail;
  if (detail == null || detail.trim().isEmpty) {
    return base;
  }
  return l10n.gsErrorWithDetail(base, detail);
}
