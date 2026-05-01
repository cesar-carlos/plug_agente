import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/general_config_section.dart';
import 'package:plug_agente/presentation/providers/system_settings_error.dart';
import 'package:plug_agente/presentation/providers/system_settings_provider.dart';
import 'package:plug_agente/presentation/providers/theme_provider.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:plug_agente/shared/widgets/common/navigation/app_fluent_tab_view.dart';
import 'package:provider/provider.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({
    super.key,
  });

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  String _lastUpdateCheck = '';
  bool _isCheckingUpdates = false;

  /// `AppConstants.appVersion` é mantido em sincronia com `pubspec.yaml` pelo
  /// script `installer/update_version.py`. Usamos a constante diretamente para
  /// evitar a piscada que ocorria entre o fallback síncrono e o resultado
  /// assíncrono do `package_info_plus`.
  String get _appVersion => AppConstants.appVersion;

  String _formatLastUpdateCheck(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _getUpdateUnavailableMessage(AppLocalizations l10n) {
    final capabilities = getIt<RuntimeCapabilities>();
    return capabilities.supportsAutoUpdate
        ? '${l10n.configAutoUpdateNotConfigured}\n${l10n.configAutoUpdateOfficialFeedExpected(officialAutoUpdateFeedUrl)}'
        : l10n.configAutoUpdateNotSupported;
  }

  String _formatTechnicalDetails(
    AppLocalizations l10n,
    UpdateCheckDiagnostics? diagnostics,
  ) {
    if (diagnostics == null) {
      return l10n.configUpdateTechnicalNoData;
    }

    final lines = <String>[
      l10n.configUpdateTechnicalTitle,
      '${l10n.configUpdateTechnicalCurrentVersion}: $_appVersion',
      '${l10n.configUpdateTechnicalCheckedAt}: ${_formatLastUpdateCheck(diagnostics.checkedAt)}',
      '${l10n.configUpdateTechnicalConfiguredFeed}: ${diagnostics.configuredFeedUrl}',
      '${l10n.configUpdateTechnicalRequestedFeed}: ${diagnostics.requestedFeedUrl}',
      '${l10n.configUpdateTechnicalOfficialFeed}: ${isOfficialAutoUpdateFeedUrl(diagnostics.configuredFeedUrl) ? l10n.configUpdateTechnicalOfficialFeedYes : l10n.configUpdateTechnicalOfficialFeedNo}',
    ];

    if (diagnostics.appcastProbeItemCount != null) {
      lines.add(
        '${l10n.configUpdateTechnicalFeedItemCount}: ${diagnostics.appcastProbeItemCount}',
      );
    }

    if (diagnostics.remoteVersion != null && diagnostics.remoteVersion!.isNotEmpty) {
      lines.add(
        '${l10n.configUpdateTechnicalRemoteVersion}: ${diagnostics.remoteVersion}',
      );
    } else if (diagnostics.appcastProbeVersion != null && diagnostics.appcastProbeVersion!.isNotEmpty) {
      lines.add(
        '${l10n.configUpdateTechnicalRemoteVersion}: ${diagnostics.appcastProbeVersion}',
      );
    }

    if (diagnostics.errorMessage != null && diagnostics.errorMessage!.isNotEmpty) {
      lines.add(
        '${l10n.configUpdateTechnicalUpdaterError}: ${diagnostics.errorMessage}',
      );
    } else if (diagnostics.probeErrorMessage != null && diagnostics.probeErrorMessage!.isNotEmpty) {
      lines.add(
        '${l10n.configUpdateTechnicalAppcastError}: ${diagnostics.probeErrorMessage}',
      );
    }

    return lines.join('\n');
  }

  Future<void> _checkUpdates() async {
    if (_isCheckingUpdates) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final orchestrator = getIt<IAutoUpdateOrchestrator>();
    if (!orchestrator.isAvailable) {
      SettingsFeedback.showError(
        context: context,
        title: l10n.gsSectionUpdates,
        message: _getUpdateUnavailableMessage(l10n),
      );
      return;
    }

    setState(() {
      _lastUpdateCheck = l10n.configUpdatesChecking;
      _isCheckingUpdates = true;
    });

    final result = await orchestrator.checkManual();

    if (!mounted) {
      return;
    }

    final checkedAt = _formatLastUpdateCheck(DateTime.now());
    setState(() {
      _lastUpdateCheck = '${l10n.configLastUpdatePrefix}$checkedAt';
      _isCheckingUpdates = false;
    });

    result.fold(
      (isUpdateAvailable) {
        final message = isUpdateAvailable
            ? l10n.configUpdatesAvailable
            : '${l10n.configUpdatesNotAvailable}\n${l10n.configUpdatesNotAvailableHint}';
        final technicalDetails = _formatTechnicalDetails(
          l10n,
          orchestrator.lastManualDiagnostics,
        );
        return SettingsFeedback.showInfo(
          context: context,
          title: l10n.gsSectionUpdates,
          message: '$message\n\n$technicalDetails',
        );
      },
      (failure) {
        final technicalDetails = _formatTechnicalDetails(
          l10n,
          orchestrator.lastManualDiagnostics,
        );
        return SettingsFeedback.showError(
          context: context,
          title: l10n.gsSectionUpdates,
          message: '${failure.toDisplayMessage()}\n\n$technicalDetails',
        );
      },
    );
  }

  Future<void> _onStartWithWindowsChanged(
    SystemSettingsProvider provider,
    bool value,
  ) async {
    final outcome = await provider.setStartWithWindows(value);
    if (!mounted || outcome == null) {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final themeProvider = context.watch<ThemeProvider>();
    final systemSettingsProvider = context.watch<SystemSettingsProvider>();
    final startupSupported = getIt.isRegistered<IStartupService>();
    final capabilities = getIt<RuntimeCapabilities>();
    final supportsAutoUpdate = capabilities.supportsAutoUpdate;

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
            appVersion: _appVersion,
            isDarkThemeEnabled: themeProvider.isDarkMode,
            startWithWindows: systemSettingsProvider.startWithWindows,
            startMinimized: systemSettingsProvider.startMinimized,
            minimizeToTray: systemSettingsProvider.minimizeToTray,
            closeToTray: systemSettingsProvider.closeToTray,
            lastUpdateCheck: _lastUpdateCheck,
            isCheckingUpdates: _isCheckingUpdates,
            startupSupported: startupSupported,
            startupError: systemSettingsProvider.lastError,
            supportsAutoUpdate: supportsAutoUpdate,
            onDarkThemeChanged: themeProvider.setIsDarkMode,
            onStartWithWindowsChanged: (bool value) => _onStartWithWindowsChanged(
              systemSettingsProvider,
              value,
            ),
            onStartMinimizedChanged: systemSettingsProvider.setStartMinimized,
            onMinimizeToTrayChanged: systemSettingsProvider.setMinimizeToTray,
            onCloseToTrayChanged: systemSettingsProvider.setCloseToTray,
            onOpenStartupSettings: systemSettingsProvider.openStartupSettings,
            onCheckUpdates: _checkUpdates,
          ),
        ),
      ),
    );
  }
}

class _ConfigTabbedContent extends StatefulWidget {
  const _ConfigTabbedContent({
    required this.appVersion,
    required this.isDarkThemeEnabled,
    required this.startWithWindows,
    required this.startMinimized,
    required this.minimizeToTray,
    required this.closeToTray,
    required this.lastUpdateCheck,
    required this.isCheckingUpdates,
    required this.startupSupported,
    required this.startupError,
    required this.supportsAutoUpdate,
    required this.onDarkThemeChanged,
    required this.onStartWithWindowsChanged,
    required this.onStartMinimizedChanged,
    required this.onMinimizeToTrayChanged,
    required this.onCloseToTrayChanged,
    required this.onOpenStartupSettings,
    required this.onCheckUpdates,
  });

  final String appVersion;
  final bool isDarkThemeEnabled;
  final bool startWithWindows;
  final bool startMinimized;
  final bool minimizeToTray;
  final bool closeToTray;
  final String lastUpdateCheck;
  final bool isCheckingUpdates;
  final bool startupSupported;
  final SystemSettingsErrorState? startupError;
  final bool supportsAutoUpdate;
  final ValueChanged<bool> onDarkThemeChanged;
  final ValueChanged<bool> onStartWithWindowsChanged;
  final ValueChanged<bool> onStartMinimizedChanged;
  final ValueChanged<bool> onMinimizeToTrayChanged;
  final ValueChanged<bool> onCloseToTrayChanged;
  final VoidCallback onOpenStartupSettings;
  final VoidCallback onCheckUpdates;

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
          text: l10n.configTabGeneral,
          body: GeneralConfigSection(
            appVersion: widget.appVersion,
            isDarkThemeEnabled: widget.isDarkThemeEnabled,
            startWithWindows: widget.startWithWindows,
            startMinimized: widget.startMinimized,
            minimizeToTray: widget.minimizeToTray,
            closeToTray: widget.closeToTray,
            lastUpdateCheck: widget.lastUpdateCheck,
            isCheckingUpdates: widget.isCheckingUpdates,
            startupSupported: widget.startupSupported,
            startupError: widget.startupError,
            supportsAutoUpdate: widget.supportsAutoUpdate,
            onDarkThemeChanged: widget.onDarkThemeChanged,
            onStartWithWindowsChanged: widget.onStartWithWindowsChanged,
            onStartMinimizedChanged: widget.onStartMinimizedChanged,
            onMinimizeToTrayChanged: widget.onMinimizeToTrayChanged,
            onCloseToTrayChanged: widget.onCloseToTrayChanged,
            onOpenStartupSettings: widget.onOpenStartupSettings,
            onCheckUpdates: widget.onCheckUpdates,
          ),
        ),
      ],
    );
  }
}
