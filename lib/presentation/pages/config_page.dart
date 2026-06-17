import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/models/updates_config_view_state.dart';
import 'package:plug_agente/presentation/pages/config/widgets/backup_config_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/preferences_config_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/updates_about_config_section.dart';
import 'package:plug_agente/presentation/providers/presentation_provider_read.dart';
import 'package:plug_agente/presentation/providers/system_settings_error.dart';
import 'package:plug_agente/presentation/providers/system_settings_provider.dart';
import 'package:plug_agente/presentation/providers/theme_provider.dart';
import 'package:plug_agente/presentation/providers/updates_settings_provider.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/navigation/app_fluent_tab_view.dart';
import 'package:provider/provider.dart';

class ConfigPage extends StatelessWidget {
  const ConfigPage({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final capabilities = getIt<RuntimeCapabilities>();
    final supportsTray = capabilities.supportsTray;
    final isDarkThemeEnabled = context.select<ThemeProvider, bool>((provider) => provider.isDarkMode);
    final themeError = context.select<ThemeProvider, SystemSettingsErrorState?>(
      (provider) => provider.persistenceError,
    );
    final systemSettings = context.select<SystemSettingsProvider, _ConfigSystemSettingsViewState>(
      (provider) => _ConfigSystemSettingsViewState(
        startWithWindows: provider.startWithWindows,
        startMinimized: provider.startMinimized,
        minimizeToTray: provider.minimizeToTray,
        closeToTray: provider.closeToTray,
        startupError: provider.startupError,
        preferenceError: provider.preferenceError,
        startupNotice: provider.startupNotice,
      ),
    );
    final themeProvider = context.read<ThemeProvider>();
    final systemSettingsProvider = context.read<SystemSettingsProvider>();
    final startupSupported = readOptionalGetItService<IStartupService>() != null;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          l10n.navSettings,
          style: context.sectionTitle,
        ),
      ),
      content: Padding(
        padding: AppLayout.pagePadding(context),
        child: AppLayout.centeredContent(
          child: _ConfigTabbedContent(
            isDarkThemeEnabled: isDarkThemeEnabled,
            startWithWindows: systemSettings.startWithWindows,
            startMinimized: systemSettings.startMinimized,
            minimizeToTray: supportsTray && systemSettings.minimizeToTray,
            closeToTray: supportsTray && systemSettings.closeToTray,
            startupSupported: startupSupported,
            startMinimizedSupported: supportsTray,
            trayBehaviorSupported: supportsTray,
            startupError: systemSettings.startupError,
            preferenceError: systemSettings.preferenceError,
            themeError: themeError,
            startupNotice: systemSettings.startupNotice,
            onDarkThemeChanged: themeProvider.setIsDarkMode,
            onStartWithWindowsChanged: (bool value) => _onStartWithWindowsChanged(
              context,
              systemSettingsProvider,
              value,
            ),
            onStartMinimizedChanged: systemSettingsProvider.setStartMinimized,
            onMinimizeToTrayChanged: systemSettingsProvider.setMinimizeToTray,
            onCloseToTrayChanged: systemSettingsProvider.setCloseToTray,
            onOpenStartupSettings: systemSettingsProvider.openStartupSettings,
            onRepairStartupLaunchConfiguration: systemSettingsProvider.repairStartupLaunchConfiguration,
            onCopyStartupDiagnostic: () {
              unawaited(_copyStartupDiagnostic(context, systemSettingsProvider));
            },
          ),
        ),
      ),
    );
  }

  Future<void> _onStartWithWindowsChanged(
    BuildContext context,
    SystemSettingsProvider provider,
    bool value,
  ) async {
    final outcome = await provider.setStartWithWindows(value);
    if (!context.mounted || outcome == null) {
      return;
    }
    if (provider.preferenceError != null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final message = outcome == StartupChangeOutcome.enabled
        ? l10n.gsStartupEnabledSuccess
        : l10n.gsStartupDisabledSuccess;
    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: Text(message),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
  }

  Future<void> _copyStartupDiagnostic(
    BuildContext context,
    SystemSettingsProvider provider,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final copied = await provider.copyStartupDiagnosticToClipboard();
    if (!context.mounted) {
      return;
    }
    if (copied) {
      await SettingsFeedback.showSuccess(
        context: context,
        title: l10n.gsSectionSystem,
        message: l10n.configStartupDiagnosticsCopied,
      );
      return;
    }
    SettingsFeedback.showError(
      context: context,
      title: l10n.gsSectionSystem,
      message: l10n.configStartupDiagnosticsCopyFailed,
    );
  }
}

class _ConfigTabbedContent extends StatefulWidget {
  const _ConfigTabbedContent({
    required this.isDarkThemeEnabled,
    required this.startWithWindows,
    required this.startMinimized,
    required this.minimizeToTray,
    required this.closeToTray,
    required this.startupSupported,
    required this.startMinimizedSupported,
    required this.trayBehaviorSupported,
    required this.startupError,
    required this.preferenceError,
    required this.themeError,
    required this.startupNotice,
    required this.onDarkThemeChanged,
    required this.onStartWithWindowsChanged,
    required this.onStartMinimizedChanged,
    required this.onMinimizeToTrayChanged,
    required this.onCloseToTrayChanged,
    required this.onOpenStartupSettings,
    required this.onRepairStartupLaunchConfiguration,
    required this.onCopyStartupDiagnostic,
  });

  final bool isDarkThemeEnabled;
  final bool startWithWindows;
  final bool startMinimized;
  final bool minimizeToTray;
  final bool closeToTray;
  final bool startupSupported;
  final bool startMinimizedSupported;
  final bool trayBehaviorSupported;
  final SystemSettingsErrorState? startupError;
  final SystemSettingsErrorState? preferenceError;
  final SystemSettingsErrorState? themeError;
  final SystemSettingsNoticeState? startupNotice;
  final ValueChanged<bool> onDarkThemeChanged;
  final ValueChanged<bool> onStartWithWindowsChanged;
  final ValueChanged<bool> onStartMinimizedChanged;
  final ValueChanged<bool> onMinimizeToTrayChanged;
  final ValueChanged<bool> onCloseToTrayChanged;
  final VoidCallback onOpenStartupSettings;
  final VoidCallback onRepairStartupLaunchConfiguration;
  final VoidCallback onCopyStartupDiagnostic;

  @override
  State<_ConfigTabbedContent> createState() => _ConfigTabbedContentState();
}

class _ConfigTabbedContentState extends State<_ConfigTabbedContent> {
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppFluentTabView(
      currentIndex: _selectedTabIndex,
      onChanged: (int index) {
        if (index == _selectedTabIndex) {
          return;
        }

        setState(() => _selectedTabIndex = index);
      },
      items: <AppFluentTabItem>[
        AppFluentTabItem(
          icon: FluentIcons.settings,
          text: l10n.configTabPreferences,
          body: PreferencesConfigSection(
            isDarkThemeEnabled: widget.isDarkThemeEnabled,
            startWithWindows: widget.startWithWindows,
            startMinimized: widget.startMinimized,
            minimizeToTray: widget.minimizeToTray,
            closeToTray: widget.closeToTray,
            startupSupported: widget.startupSupported,
            startMinimizedSupported: widget.startMinimizedSupported,
            trayBehaviorSupported: widget.trayBehaviorSupported,
            startupError: widget.startupError,
            preferenceError: widget.preferenceError,
            themeError: widget.themeError,
            startupNotice: widget.startupNotice,
            onDarkThemeChanged: widget.onDarkThemeChanged,
            onStartWithWindowsChanged: widget.onStartWithWindowsChanged,
            onStartMinimizedChanged: widget.onStartMinimizedChanged,
            onMinimizeToTrayChanged: widget.onMinimizeToTrayChanged,
            onCloseToTrayChanged: widget.onCloseToTrayChanged,
            onOpenStartupSettings: widget.onOpenStartupSettings,
            onRepairStartupLaunchConfiguration: widget.onRepairStartupLaunchConfiguration,
            onCopyStartupDiagnostic: widget.onCopyStartupDiagnostic,
          ),
        ),
        AppFluentTabItem(
          icon: FluentIcons.download,
          text: l10n.configTabUpdatesAbout,
          body: const _ConfigUpdatesTab(),
        ),
        AppFluentTabItem(
          icon: FluentIcons.save,
          text: l10n.configTabBackup,
          body: const BackupConfigSection(),
        ),
      ],
    );
  }
}

class _ConfigUpdatesTab extends StatelessWidget {
  const _ConfigUpdatesTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final updatesState = context.select<UpdatesSettingsProvider, UpdatesConfigViewState>(
      (provider) => UpdatesConfigViewState.fromProvider(provider, l10n),
    );
    final updates = context.read<UpdatesSettingsProvider>();

    return UpdatesAboutConfigSection(
      appVersion: updatesState.appVersion,
      lastUpdateCheck: updatesState.lastUpdateCheck,
      lastBackgroundUpdateCheck: updatesState.lastBackgroundUpdateCheck,
      lastAutomaticUpdateCheck: updatesState.lastAutomaticUpdateCheck,
      autoUpdateFeedStatus: updatesState.autoUpdateFeedStatus,
      updateNotificationsEnabled: updatesState.updateNotificationsEnabled,
      automaticSilentUpdatesEnabled: updatesState.automaticSilentUpdatesEnabled,
      isCheckingUpdates: updatesState.isCheckingUpdates,
      isCheckingAutomaticUpdates: updatesState.isCheckingAutomaticUpdates,
      isAutoUpdateAvailable: updatesState.isAutoUpdateAvailable,
      unavailableMessage: updatesState.autoUpdateUnavailableMessage,
      releaseNotes: updatesState.releaseNotes,
      releaseNotesUrl: updatesState.releaseNotesUrl,
      onCheckUpdates: () => updates.checkUpdates(context),
      onCheckAutomaticUpdates: () => updates.checkAutomaticUpdatesNow(context),
      onCopyUpdateDiagnostics: () => updates.copyUpdateDiagnostics(context),
      onUpdateNotificationsChanged: (value) {
        unawaited(updates.setUpdateNotificationsEnabled(context, value));
      },
      onAutomaticSilentUpdatesChanged: (value) {
        unawaited(updates.setAutomaticSilentUpdatesEnabled(context, value));
      },
      onUseManualOnlyUpdateMode: () {
        unawaited(updates.applyManualOnlyUpdateMode(context));
      },
      pendingUpdateNotice: updatesState.pendingUpdateNotice,
      updateCheckNotice: updatesState.updateCheckNotice,
    );
  }
}

@immutable
class _ConfigSystemSettingsViewState {
  const _ConfigSystemSettingsViewState({
    required this.startWithWindows,
    required this.startMinimized,
    required this.minimizeToTray,
    required this.closeToTray,
    required this.startupError,
    required this.preferenceError,
    required this.startupNotice,
  });

  final bool startWithWindows;
  final bool startMinimized;
  final bool minimizeToTray;
  final bool closeToTray;
  final SystemSettingsErrorState? startupError;
  final SystemSettingsErrorState? preferenceError;
  final SystemSettingsNoticeState? startupNotice;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _ConfigSystemSettingsViewState &&
            startWithWindows == other.startWithWindows &&
            startMinimized == other.startMinimized &&
            minimizeToTray == other.minimizeToTray &&
            closeToTray == other.closeToTray &&
            startupError == other.startupError &&
            preferenceError == other.preferenceError &&
            startupNotice == other.startupNotice;
  }

  @override
  int get hashCode => Object.hash(
    startWithWindows,
    startMinimized,
    minimizeToTray,
    closeToTray,
    startupError,
    preferenceError,
    startupNotice,
  );
}
