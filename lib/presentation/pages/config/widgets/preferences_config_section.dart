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
    required this.onRepairStartupLaunchConfiguration,
    this.startupSupported = true,
    this.startMinimizedSupported = true,
    this.startupError,
    this.preferenceError,
    this.startupNotice,
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
  final VoidCallback onRepairStartupLaunchConfiguration;
  final bool startupSupported;
  final bool startMinimizedSupported;
  final SystemSettingsErrorState? startupError;
  final SystemSettingsErrorState? preferenceError;
  final SystemSettingsNoticeState? startupNotice;

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
              _SystemSettingsFeedbackMessage(
                message: _translateError(l10n, startupError!),
                tone: AppFeedbackTone.error,
                icon: FluentIcons.error_badge,
                actionLabel: l10n.gsButtonOpenSettings,
                onAction: onOpenStartupSettings,
              ),
            ] else if (startupNotice != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _SystemSettingsFeedbackMessage(
                message: _translateNotice(l10n, startupNotice!),
                tone: _noticeTone(startupNotice!),
                icon: _noticeIcon(startupNotice!),
                actionLabel: startupNotice!.code == SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed
                    ? l10n.gsButtonRepairStartup
                    : null,
                onAction: startupNotice!.code == SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed
                    ? onRepairStartupLaunchConfiguration
                    : null,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: l10n.gsToggleStartMinimized,
              description: startMinimizedSupported
                  ? l10n.gsToggleStartMinimizedNextLaunchHint
                  : l10n.gsToggleStartMinimizedRequiresTray,
              value: startMinimized,
              onChanged: startMinimizedSupported ? onStartMinimizedChanged : null,
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
            if (preferenceError != null) ...[
              const SizedBox(height: AppSpacing.md),
              _SystemSettingsFeedbackMessage(
                message: _translateError(l10n, preferenceError!),
                tone: AppFeedbackTone.error,
                icon: FluentIcons.error_badge,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SystemSettingsFeedbackMessage extends StatelessWidget {
  const _SystemSettingsFeedbackMessage({
    required this.message,
    required this.tone,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final AppFeedbackTone tone;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final feedbackColors = context.appColors.feedback(tone);
    final actionLabel = this.actionLabel;
    final onAction = this.onAction;

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
            icon,
            color: feedbackColors.accent,
            size: 16,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: context.captionText.copyWith(
                color: feedbackColors.accent,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: actionLabel,
              filledBackgroundColor: feedbackColors.background,
              filledForegroundColor: feedbackColors.accent,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

String _translateError(AppLocalizations l10n, SystemSettingsErrorState error) {
  final base = switch (error.code) {
    SystemSettingsErrorCode.startupToggleFailed => l10n.gsErrorStartupToggleFailed,
    SystemSettingsErrorCode.startupServiceUnavailable => l10n.gsErrorStartupServiceUnavailable,
    SystemSettingsErrorCode.startupOpenSystemSettingsFailed => l10n.gsErrorStartupOpenSystemSettingsFailed,
    SystemSettingsErrorCode.settingsPersistenceFailed => l10n.gsErrorSettingsPersistenceFailed,
  };
  final detail = error.detail;
  if (detail == null || detail.trim().isEmpty) {
    return base;
  }
  return l10n.gsErrorWithDetail(base, detail);
}

String _translateNotice(AppLocalizations l10n, SystemSettingsNoticeState notice) {
  final base = switch (notice.code) {
    SystemSettingsNoticeCode.startupLaunchConfigurationReady => l10n.gsStartupLaunchConfigurationReady,
    SystemSettingsNoticeCode.startupLaunchConfigurationRepaired => l10n.gsStartupLaunchConfigurationRepaired,
    SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed => l10n.gsStartupLaunchConfigurationRepairFailed,
  };
  final detail = notice.detail;
  if (detail == null || detail.trim().isEmpty) {
    return base;
  }
  return l10n.gsErrorWithDetail(base, detail);
}

AppFeedbackTone _noticeTone(SystemSettingsNoticeState notice) {
  return switch (notice.code) {
    SystemSettingsNoticeCode.startupLaunchConfigurationReady => AppFeedbackTone.info,
    SystemSettingsNoticeCode.startupLaunchConfigurationRepaired => AppFeedbackTone.success,
    SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed => AppFeedbackTone.warning,
  };
}

IconData _noticeIcon(SystemSettingsNoticeState notice) {
  return switch (notice.code) {
    SystemSettingsNoticeCode.startupLaunchConfigurationReady => FluentIcons.info,
    SystemSettingsNoticeCode.startupLaunchConfigurationRepaired => FluentIcons.completed,
    SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed => FluentIcons.warning,
  };
}
