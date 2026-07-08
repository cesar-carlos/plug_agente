import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/policies/app_preferences_policy.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
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
    required this.onCopyStartupDiagnostic,
    this.startupSupported = true,
    this.startMinimizedSupported = true,
    this.trayBehaviorSupported = true,
    this.startupError,
    this.preferenceError,
    this.themeError,
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
  final VoidCallback onCopyStartupDiagnostic;
  final bool startupSupported;
  final bool startMinimizedSupported;
  final bool trayBehaviorSupported;
  final SystemSettingsErrorState? startupError;
  final SystemSettingsErrorState? preferenceError;
  final SystemSettingsErrorState? themeError;
  final SystemSettingsNoticeState? startupNotice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final startMinimizedEnabled = AppPreferencesPolicy.canConfigureStartMinimized(
      supportsTray: startMinimizedSupported,
      startWithWindows: startWithWindows,
    );
    final startMinimizedDescription = !startMinimizedSupported
        ? l10n.gsToggleStartMinimizedRequiresTray
        : !startWithWindows
        ? l10n.gsToggleStartMinimizedRequiresStartup
        : l10n.gsToggleStartMinimizedNextLaunchHint;
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
            if (themeError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _SystemSettingsFeedbackMessage(
                message: _translateError(l10n, themeError!),
                tone: AppFeedbackTone.error,
                icon: FluentIcons.error_badge,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.lg),
            SettingsSectionTitle(title: l10n.gsSectionSystem),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: l10n.gsToggleStartWithWindows,
              description: startupSupported ? l10n.gsToggleStartWithWindowsAdminHint : null,
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
                actionLabel: _showsRepairAction(startupNotice!.code) ? l10n.gsButtonRepairStartup : null,
                onAction: _showsRepairAction(startupNotice!.code) ? onRepairStartupLaunchConfiguration : null,
                secondaryActionLabel: _showsDiagnosticAction(startupNotice!.code)
                    ? l10n.gsButtonCopyStartupDiagnostic
                    : null,
                onSecondaryAction: _showsDiagnosticAction(startupNotice!.code) ? onCopyStartupDiagnostic : null,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: l10n.gsToggleStartMinimized,
              description: startMinimizedDescription,
              value: startMinimized,
              onChanged: startMinimizedEnabled ? onStartMinimizedChanged : null,
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: l10n.gsToggleMinimizeToTray,
              description: trayBehaviorSupported ? null : l10n.gsToggleStartMinimizedRequiresTray,
              value: minimizeToTray,
              onChanged: trayBehaviorSupported ? onMinimizeToTrayChanged : null,
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: l10n.gsToggleCloseToTray,
              description: trayBehaviorSupported ? null : l10n.gsToggleStartMinimizedRequiresTray,
              value: closeToTray,
              onChanged: trayBehaviorSupported ? onCloseToTrayChanged : null,
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
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final String message;
  final AppFeedbackTone tone;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final feedbackColors = context.appColors.feedback(tone);
    final actionLabel = this.actionLabel;
    final onAction = this.onAction;
    final secondaryActionLabel = this.secondaryActionLabel;
    final onSecondaryAction = this.onSecondaryAction;

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
        crossAxisAlignment: CrossAxisAlignment.start,
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
          if (secondaryActionLabel != null && onSecondaryAction != null) ...[
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: secondaryActionLabel,
              filledBackgroundColor: feedbackColors.background,
              filledForegroundColor: feedbackColors.accent,
              onPressed: onSecondaryAction,
            ),
          ],
        ],
      ),
    );
  }
}

bool _showsRepairAction(SystemSettingsNoticeCode code) {
  return code == SystemSettingsNoticeCode.startupLaunchConfigurationNeedsRepair ||
      code == SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed ||
      code == SystemSettingsNoticeCode.startupLaunchConfigurationRepairedWithLegacyEntry;
}

bool _showsDiagnosticAction(SystemSettingsNoticeCode code) {
  return code == SystemSettingsNoticeCode.startupLaunchConfigurationNeedsRepair ||
      code == SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed ||
      code == SystemSettingsNoticeCode.startupLaunchConfigurationRepairedWithLegacyEntry;
}

String _translateError(AppLocalizations l10n, SystemSettingsErrorState error) {
  final base = switch (error.code) {
    SystemSettingsErrorCode.startupToggleFailed => l10n.gsErrorStartupToggleFailed,
    SystemSettingsErrorCode.startupServiceUnavailable => l10n.gsErrorStartupServiceUnavailable,
    SystemSettingsErrorCode.startupOpenSystemSettingsFailed => l10n.gsErrorStartupOpenSystemSettingsFailed,
    SystemSettingsErrorCode.settingsPersistenceFailed => l10n.gsErrorSettingsPersistenceFailed,
  };
  if (error.code == SystemSettingsErrorCode.startupToggleFailed) {
    return _appendStartupFailureHint(l10n, base, error.startupFailureCode);
  }
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
    SystemSettingsNoticeCode.startupLaunchConfigurationNeedsRepair => l10n.gsStartupLaunchConfigurationNeedsRepair,
    SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed => l10n.gsStartupLaunchConfigurationRepairFailed,
    SystemSettingsNoticeCode.startupLaunchConfigurationRepairedWithLegacyEntry =>
      l10n.gsStartupLaunchConfigurationRepairedWithLegacyEntry,
  };
  final withHint = _appendStartupFailureHint(l10n, base, notice.startupFailureCode);
  if (notice.code == SystemSettingsNoticeCode.startupLaunchConfigurationNeedsRepair &&
      notice.startupFailureCode == null) {
    return '$withHint ${l10n.gsStartupFailureDuplicateEntryHint}';
  }
  return withHint;
}

String _appendStartupFailureHint(
  AppLocalizations l10n,
  String base,
  StartupServiceFailureCode? failureCode,
) {
  final hint = _startupFailureHint(l10n, failureCode);
  if (hint == null) {
    return base;
  }
  return '$base $hint';
}

String? _startupFailureHint(AppLocalizations l10n, StartupServiceFailureCode? code) {
  return switch (code) {
    StartupServiceFailureCode.uacCancelled => l10n.gsStartupFailureUacCancelled,
    StartupServiceFailureCode.accessDenied => l10n.gsStartupFailureAccessDenied,
    StartupServiceFailureCode.registryDeleteFailed => l10n.gsStartupFailureRegistryDelete,
    StartupServiceFailureCode.registryWriteFailed => l10n.gsStartupFailureRegistryWrite,
    StartupServiceFailureCode.registryReadFailed => l10n.gsStartupFailureRegistryRead,
    StartupServiceFailureCode.unknown || StartupServiceFailureCode.unsupportedPlatform || null => null,
  };
}

AppFeedbackTone _noticeTone(SystemSettingsNoticeState notice) {
  return switch (notice.code) {
    SystemSettingsNoticeCode.startupLaunchConfigurationReady => AppFeedbackTone.info,
    SystemSettingsNoticeCode.startupLaunchConfigurationRepaired => AppFeedbackTone.success,
    SystemSettingsNoticeCode.startupLaunchConfigurationNeedsRepair => AppFeedbackTone.warning,
    SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed => AppFeedbackTone.warning,
    SystemSettingsNoticeCode.startupLaunchConfigurationRepairedWithLegacyEntry => AppFeedbackTone.info,
  };
}

IconData _noticeIcon(SystemSettingsNoticeState notice) {
  return switch (notice.code) {
    SystemSettingsNoticeCode.startupLaunchConfigurationReady => FluentIcons.info,
    SystemSettingsNoticeCode.startupLaunchConfigurationRepaired => FluentIcons.completed,
    SystemSettingsNoticeCode.startupLaunchConfigurationNeedsRepair => FluentIcons.warning,
    SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed => FluentIcons.warning,
    SystemSettingsNoticeCode.startupLaunchConfigurationRepairedWithLegacyEntry => FluentIcons.info,
  };
}
