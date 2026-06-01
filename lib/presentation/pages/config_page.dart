import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/support/runtime_support_diagnostics_builder.dart';
import 'package:plug_agente/core/support/support_diagnostics_section.dart';
import 'package:plug_agente/core/support/support_diagnostics_text_formatter.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/models/update_check_inline_notice.dart';
import 'package:plug_agente/presentation/pages/config/widgets/backup_config_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/preferences_config_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/updates_about_config_section.dart';
import 'package:plug_agente/presentation/providers/system_settings_error.dart';
import 'package:plug_agente/presentation/providers/system_settings_provider.dart';
import 'package:plug_agente/presentation/providers/theme_provider.dart';
import 'package:plug_agente/presentation/support/update_support_diagnostics_builder.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';
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
  static const SupportDiagnosticsTextFormatter _supportTextFormatter = SupportDiagnosticsTextFormatter();
  static const RuntimeSupportDiagnosticsBuilder _runtimeDiagnosticsBuilder = RuntimeSupportDiagnosticsBuilder();
  static const UpdateSupportDiagnosticsBuilder _updateDiagnosticsBuilder = UpdateSupportDiagnosticsBuilder();

  String _lastUpdateCheck = '';
  bool _isCheckingUpdates = false;
  bool _hasPendingDownloadedUpdate = false;
  UpdateCheckInlineNotice? _updateCheckInlineNotice;
  StreamSubscription<void>? _orchestratorChangesSubscription;

  @override
  void initState() {
    super.initState();
    if (getIt.isRegistered<IAutoUpdateOrchestrator>()) {
      final orchestrator = getIt<IAutoUpdateOrchestrator>();
      _orchestratorChangesSubscription = orchestrator.changes.listen((_) {
        unawaited(_refreshPendingUpdateState());
      });
      unawaited(_refreshPendingUpdateState());
    }
  }

  @override
  void dispose() {
    _orchestratorChangesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshPendingUpdateState() async {
    if (!getIt.isRegistered<IAutoUpdateOrchestrator>()) {
      return;
    }
    final orchestrator = getIt<IAutoUpdateOrchestrator>();
    final hasPending = await orchestrator.hasPendingDownloadedUpdate;
    if (!mounted) {
      return;
    }
    if (_hasPendingDownloadedUpdate != hasPending) {
      setState(() => _hasPendingDownloadedUpdate = hasPending);
    }
  }

  String? _resolvePendingUpdateNotice(
    AppLocalizations l10n,
    IAutoUpdateOrchestrator orchestrator,
  ) {
    if (orchestrator.updateNotificationsEnabled) {
      return null;
    }
    if (_hasPendingDownloadedUpdate) {
      return l10n.configUpdatePendingReadyNotice;
    }
    if (orchestrator.hasUpdateAwaitingUserConsent) {
      return l10n.configUpdatePendingAwaitingConsentNotice;
    }
    return null;
  }

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
    if (!capabilities.supportsAutoUpdate) {
      return l10n.configAutoUpdateNotSupported;
    }

    if (hasInvalidAutoUpdateFeedOverride(environment: AppEnvironment.snapshot())) {
      return '${l10n.configAutoUpdateNotConfigured}\n${l10n.configAutoUpdateOfficialFeedExpected(officialAutoUpdateFeedUrl)}';
    }

    return l10n.configAutoUpdateNotSupported;
  }

  String _buildBackgroundUpdateLabel(
    AppLocalizations l10n,
    UpdateCheckDiagnostics? diagnostics,
  ) {
    if (diagnostics == null) {
      return '';
    }

    final checkedAt = _formatLastUpdateCheck(diagnostics.checkedAt);
    final completion = diagnostics.completionSource == null
        ? ''
        : ' - ${UpdateSupportDiagnosticsBuilder.formatCompletionSource(l10n, diagnostics.completionSource)}';
    return '${l10n.configLastBackgroundUpdatePrefix}$checkedAt$completion';
  }

  String _buildAutomaticUpdateLabel(
    AppLocalizations l10n,
    UpdateCheckDiagnostics? diagnostics,
  ) {
    if (diagnostics == null) {
      return '${l10n.configLastAutomaticUpdatePrefix}${l10n.configLastUpdateNever}';
    }

    final checkedAt = _formatLastUpdateCheck(diagnostics.checkedAt);
    final completion = diagnostics.completionSource == null
        ? ''
        : ' - ${UpdateSupportDiagnosticsBuilder.formatCompletionSource(l10n, diagnostics.completionSource)}';
    return '${l10n.configLastAutomaticUpdatePrefix}$checkedAt$completion';
  }

  String _buildAutoUpdateFeedStatusLabel(AppLocalizations l10n) {
    final feedUrl = resolveAutoUpdateFeedUrl(environment: AppEnvironment.snapshot());
    if (isOfficialAutoUpdateFeedUrl(feedUrl)) {
      return l10n.configAutoUpdateFeedOfficial;
    }
    return l10n.configAutoUpdateFeedCustom;
  }

  List<SupportDiagnosticsSection> _buildUpdateDiagnosticSections(
    AppLocalizations l10n,
    IAutoUpdateOrchestrator orchestrator, {
    UpdateCheckDiagnostics? manualDiagnostics,
    UpdateCheckDiagnostics? backgroundDiagnostics,
    UpdateCheckDiagnostics? automaticDiagnostics,
  }) {
    return _updateDiagnosticsBuilder.buildSections(
      l10n: l10n,
      currentAppVersion: _appVersion,
      manualDiagnostics: manualDiagnostics ?? orchestrator.lastManualDiagnostics,
      backgroundDiagnostics: backgroundDiagnostics ?? orchestrator.lastBackgroundDiagnostics,
      automaticDiagnostics: automaticDiagnostics ?? orchestrator.lastAutomaticDiagnostics,
    );
  }

  Future<void> _showUpdateDiagnosticsDialog({
    required AppLocalizations l10n,
    required String message,
    required List<SupportDiagnosticsSection> sections,
    MessageType type = MessageType.info,
  }) {
    return SettingsFeedback.showWithDiagnostics(
      context: context,
      title: l10n.gsSectionUpdates,
      message: message,
      type: type,
      diagnosticSections: sections,
      onCopyDiagnostics: _copyUpdateDiagnostics,
      collapseDiagnosticsByDefault: type == MessageType.info,
    );
  }

  void _setUpdateCheckInlineNotice(UpdateCheckInlineNotice notice) {
    setState(() {
      _updateCheckInlineNotice = notice;
    });
  }

  String _buildUpdateSupportDiagnostics(
    AppLocalizations l10n,
    IAutoUpdateOrchestrator orchestrator,
  ) {
    final sections = <SupportDiagnosticsSection>[
      SupportDiagnosticsSection(
        title: 'Plug Agente Auto-Update',
        fields: <SupportDiagnosticsField>[
          SupportDiagnosticsField(
            key: l10n.gsLabelVersion,
            value: _appVersion,
          ),
        ],
      ),
      if (_buildRuntimeSupportDiagnostics() case final SupportDiagnosticsSection runtimeSection) runtimeSection,
      ..._updateDiagnosticsBuilder.buildSections(
        l10n: l10n,
        currentAppVersion: _appVersion,
        manualDiagnostics: orchestrator.lastManualDiagnostics,
        backgroundDiagnostics: orchestrator.lastBackgroundDiagnostics,
        automaticDiagnostics: orchestrator.lastAutomaticDiagnostics,
        updateNotificationsEnabled: orchestrator.updateNotificationsEnabled,
        automaticSilentUpdatesEnabled: orchestrator.automaticSilentUpdatesEnabled,
      ),
    ];

    return _supportTextFormatter.formatSections(sections);
  }

  SupportDiagnosticsSection? _buildRuntimeSupportDiagnostics() {
    if (!getIt.isRegistered<RuntimeCapabilities>()) {
      return null;
    }

    final capabilities = getIt<RuntimeCapabilities>();
    final diagnostics = getIt.isRegistered<RuntimeDetectionDiagnostics>() ? getIt<RuntimeDetectionDiagnostics>() : null;
    return _runtimeDiagnosticsBuilder.buildSection(
      capabilities: capabilities,
      diagnostics: diagnostics,
    );
  }

  String _resolveLastUpdateLabel(
    AppLocalizations l10n,
    IAutoUpdateOrchestrator orchestrator,
  ) {
    if (_lastUpdateCheck.isNotEmpty) {
      return _lastUpdateCheck;
    }

    final manual = orchestrator.lastManualDiagnostics;
    final background = orchestrator.lastBackgroundDiagnostics;
    final latest = background == null || (manual != null && manual.checkedAt.isAfter(background.checkedAt))
        ? manual
        : background;
    if (latest == null) {
      return '';
    }

    return '${l10n.configLastUpdatePrefix}${_formatLastUpdateCheck(latest.checkedAt)}';
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
      _updateCheckInlineNotice = null;
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
      (outcome) {
        final sections = _buildUpdateDiagnosticSections(l10n, orchestrator);
        switch (outcome) {
          case ManualCheckOutcome.updateAvailable:
            return _showUpdateDiagnosticsDialog(
              l10n: l10n,
              message: l10n.configUpdatesAvailable,
              sections: sections,
              type: MessageType.success,
            );
          case ManualCheckOutcome.noUpdate:
            _setUpdateCheckInlineNotice(
              UpdateCheckInlineNotice(
                message: l10n.configUpdatesNotAvailable,
                hint: l10n.configUpdatesNotAvailableHint,
                severity: InfoBarSeverity.success,
                diagnosticSections: sections,
              ),
            );
            return Future<void>.value();
          case ManualCheckOutcome.triggerTimeout:
          case ManualCheckOutcome.completionTimeout:
          case ManualCheckOutcome.circuitOpen:
          case ManualCheckOutcome.notInitialized:
          case ManualCheckOutcome.disabled:
            final completionMessage = UpdateSupportDiagnosticsBuilder.formatCompletionSource(
              l10n,
              orchestrator.lastManualDiagnostics?.completionSource,
            );
            return _showUpdateDiagnosticsDialog(
              l10n: l10n,
              message: completionMessage,
              sections: sections,
              type: MessageType.warning,
            );
        }
      },
      (failure) {
        final sections = _buildUpdateDiagnosticSections(l10n, orchestrator);
        return _showUpdateDiagnosticsDialog(
          l10n: l10n,
          message: failure.toDisplayMessage(),
          sections: sections,
          type: MessageType.error,
        );
      },
    );
  }

  Future<void> _checkAutomaticUpdatesNow() async {
    final orchestrator = getIt<IAutoUpdateOrchestrator>();
    if (orchestrator.isSilentCheckInProgress) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    if (!orchestrator.isAvailable) {
      SettingsFeedback.showError(
        context: context,
        title: l10n.gsSectionUpdates,
        message: _getUpdateUnavailableMessage(l10n),
      );
      return;
    }

    setState(() {
      _updateCheckInlineNotice = null;
    });

    final result = await orchestrator.checkSilently();

    if (!mounted) {
      return;
    }

    // Trigger a rebuild so the button reflects isSilentCheckInProgress = false.
    setState(() {});

    result.fold(
      (outcome) {
        final sections = _buildUpdateDiagnosticSections(
          l10n,
          orchestrator,
          automaticDiagnostics: orchestrator.lastAutomaticDiagnostics,
        );
        final completionMessage = UpdateSupportDiagnosticsBuilder.formatCompletionSource(
          l10n,
          orchestrator.lastAutomaticDiagnostics?.completionSource,
        );

        switch (outcome) {
          case SilentUpdateOutcome.installerReady:
          case SilentUpdateOutcome.requiresUserConsent:
            return _showUpdateDiagnosticsDialog(
              l10n: l10n,
              message: completionMessage,
              sections: sections,
              type: MessageType.warning,
            );
          case SilentUpdateOutcome.noNewVersion:
            _setUpdateCheckInlineNotice(
              UpdateCheckInlineNotice(
                message: l10n.configUpdatesNotAvailable,
                hint: l10n.configUpdatesNotAvailableHint,
                severity: InfoBarSeverity.success,
                diagnosticSections: sections,
              ),
            );
            return Future<void>.value();
          case SilentUpdateOutcome.silentDisabled:
          case SilentUpdateOutcome.rolloutSkipped:
          case SilentUpdateOutcome.cooldownActive:
          case SilentUpdateOutcome.pendingInProgress:
          case SilentUpdateOutcome.alreadyInProgress:
          case SilentUpdateOutcome.cancelled:
          case SilentUpdateOutcome.skippedByQuietHours:
            _setUpdateCheckInlineNotice(
              UpdateCheckInlineNotice(
                message: completionMessage,
                severity: InfoBarSeverity.info,
                diagnosticSections: sections,
              ),
            );
            return Future<void>.value();
        }
      },
      (failure) {
        final sections = _buildUpdateDiagnosticSections(
          l10n,
          orchestrator,
          automaticDiagnostics: orchestrator.lastAutomaticDiagnostics,
        );
        return _showUpdateDiagnosticsDialog(
          l10n: l10n,
          message: failure.toDisplayMessage(),
          sections: sections,
          type: MessageType.error,
        );
      },
    );
  }

  Future<void> _copyUpdateDiagnostics() async {
    final l10n = AppLocalizations.of(context)!;
    final orchestrator = getIt<IAutoUpdateOrchestrator>();
    final diagnostics = _buildUpdateSupportDiagnostics(l10n, orchestrator);
    await Clipboard.setData(ClipboardData(text: diagnostics));
    if (!mounted) {
      return;
    }
    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: Text(l10n.configUpdateDiagnosticsCopied),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
  }

  Future<void> _onUpdateNotificationsChanged(bool value) async {
    final l10n = AppLocalizations.of(context)!;
    final orchestrator = getIt<IAutoUpdateOrchestrator>();
    final result = await orchestrator.setUpdateNotificationsEnabled(value);
    if (!mounted) {
      return;
    }

    result.fold(
      (_) {
        unawaited(_refreshPendingUpdateState());
        setState(() {});
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(
              value ? l10n.configUpdateNotificationsEnabled : l10n.configUpdateNotificationsDisabled,
            ),
            severity: InfoBarSeverity.success,
            onClose: close,
          ),
        );
      },
      (failure) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.gsSectionUpdates,
          message: failure.toDisplayMessage(),
        );
      },
    );
  }

  Future<void> _onUseManualOnlyUpdateMode() async {
    final l10n = AppLocalizations.of(context)!;
    final orchestrator = getIt<IAutoUpdateOrchestrator>();
    final result = await orchestrator.applyManualOnlyUpdateMode();
    if (!mounted) {
      return;
    }

    result.fold(
      (_) {
        unawaited(_refreshPendingUpdateState());
        setState(() {});
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(l10n.configManualOnlyUpdatesApplied),
            severity: InfoBarSeverity.success,
            onClose: close,
          ),
        );
      },
      (failure) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.gsSectionUpdates,
          message: failure.toDisplayMessage(),
        );
      },
    );
  }

  Future<void> _onAutomaticSilentUpdatesChanged(bool value) async {
    final l10n = AppLocalizations.of(context)!;
    final orchestrator = getIt<IAutoUpdateOrchestrator>();
    final result = await orchestrator.setAutomaticSilentUpdatesEnabled(value);
    if (!mounted) {
      return;
    }

    result.fold(
      (_) {
        unawaited(_refreshPendingUpdateState());
        setState(() {});
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: Text(
              value ? l10n.configAutomaticSilentUpdatesEnabled : l10n.configAutomaticSilentUpdatesDisabled,
            ),
            severity: InfoBarSeverity.success,
            onClose: close,
          ),
        );
        if (!value && orchestrator.updateNotificationsEnabled) {
          displayInfoBar(
            context,
            builder: (context, close) => InfoBar(
              title: Text(l10n.configAutomaticSilentUpdatesDisabled),
              content: Text(l10n.configAutomaticSilentUpdatesDisableNotificationsHint),
              onClose: close,
            ),
          );
        }
      },
      (failure) {
        SettingsFeedback.showError(
          context: context,
          title: l10n.gsSectionUpdates,
          message: failure.toDisplayMessage(),
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
    final capabilities = getIt<RuntimeCapabilities>();
    final supportsTray = capabilities.supportsTray;
    final themeProvider = context.watch<ThemeProvider>();
    final systemSettingsProvider = context.watch<SystemSettingsProvider>();
    final startupSupported = getIt.isRegistered<IStartupService>();
    final orchestrator = getIt<IAutoUpdateOrchestrator>();
    final isAutoUpdateAvailable = orchestrator.isAvailable;
    final lastUpdateLabel = _resolveLastUpdateLabel(l10n, orchestrator);
    final lastBackgroundUpdateLabel = _buildBackgroundUpdateLabel(
      l10n,
      orchestrator.lastBackgroundDiagnostics,
    );
    final lastAutomaticUpdateLabel = _buildAutomaticUpdateLabel(
      l10n,
      orchestrator.lastAutomaticDiagnostics,
    );
    final autoUpdateFeedStatusLabel = _buildAutoUpdateFeedStatusLabel(l10n);
    final autoUpdateUnavailableMessage = isAutoUpdateAvailable ? null : _getUpdateUnavailableMessage(l10n);
    final pendingUpdateNotice = _resolvePendingUpdateNotice(l10n, orchestrator);

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
            minimizeToTray: supportsTray && systemSettingsProvider.minimizeToTray,
            closeToTray: supportsTray && systemSettingsProvider.closeToTray,
            lastUpdateCheck: lastUpdateLabel,
            lastBackgroundUpdateCheck: lastBackgroundUpdateLabel,
            lastAutomaticUpdateCheck: lastAutomaticUpdateLabel,
            autoUpdateFeedStatus: autoUpdateFeedStatusLabel,
            updateNotificationsEnabled: orchestrator.updateNotificationsEnabled,
            automaticSilentUpdatesEnabled: orchestrator.automaticSilentUpdatesEnabled,
            isCheckingUpdates: _isCheckingUpdates,
            isCheckingAutomaticUpdates: orchestrator.isSilentCheckInProgress,
            startupSupported: startupSupported,
            startMinimizedSupported: supportsTray,
            trayBehaviorSupported: supportsTray,
            startupError: systemSettingsProvider.startupError,
            preferenceError: systemSettingsProvider.preferenceError,
            themeError: themeProvider.persistenceError,
            startupNotice: systemSettingsProvider.startupNotice,
            isAutoUpdateAvailable: isAutoUpdateAvailable,
            autoUpdateUnavailableMessage: autoUpdateUnavailableMessage,
            releaseNotes:
                orchestrator.lastManualDiagnostics?.releaseNotes ?? orchestrator.lastAutomaticDiagnostics?.releaseNotes,
            releaseNotesUrl:
                orchestrator.lastManualDiagnostics?.releaseNotesUrl ??
                orchestrator.lastAutomaticDiagnostics?.releaseNotesUrl,
            onDarkThemeChanged: themeProvider.setIsDarkMode,
            onStartWithWindowsChanged: (bool value) => _onStartWithWindowsChanged(
              systemSettingsProvider,
              value,
            ),
            onStartMinimizedChanged: systemSettingsProvider.setStartMinimized,
            onMinimizeToTrayChanged: systemSettingsProvider.setMinimizeToTray,
            onCloseToTrayChanged: systemSettingsProvider.setCloseToTray,
            onOpenStartupSettings: systemSettingsProvider.openStartupSettings,
            onRepairStartupLaunchConfiguration: systemSettingsProvider.repairStartupLaunchConfiguration,
            onCopyStartupDiagnostic: () {
              unawaited(systemSettingsProvider.copyStartupDiagnosticToClipboard());
            },
            onCheckUpdates: _checkUpdates,
            onCheckAutomaticUpdates: _checkAutomaticUpdatesNow,
            onCopyUpdateDiagnostics: _copyUpdateDiagnostics,
            onUpdateNotificationsChanged: (value) {
              unawaited(_onUpdateNotificationsChanged(value));
            },
            onAutomaticSilentUpdatesChanged: (value) {
              unawaited(_onAutomaticSilentUpdatesChanged(value));
            },
            onUseManualOnlyUpdateMode: () {
              unawaited(_onUseManualOnlyUpdateMode());
            },
            pendingUpdateNotice: pendingUpdateNotice,
            updateCheckNotice: _updateCheckInlineNotice,
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
    required this.lastBackgroundUpdateCheck,
    required this.lastAutomaticUpdateCheck,
    required this.autoUpdateFeedStatus,
    required this.updateNotificationsEnabled,
    required this.automaticSilentUpdatesEnabled,
    required this.isCheckingUpdates,
    required this.isCheckingAutomaticUpdates,
    required this.startupSupported,
    required this.startMinimizedSupported,
    required this.trayBehaviorSupported,
    required this.startupError,
    required this.preferenceError,
    required this.themeError,
    required this.startupNotice,
    required this.isAutoUpdateAvailable,
    required this.autoUpdateUnavailableMessage,
    required this.onDarkThemeChanged,
    required this.onStartWithWindowsChanged,
    required this.onStartMinimizedChanged,
    required this.onMinimizeToTrayChanged,
    required this.onCloseToTrayChanged,
    required this.onOpenStartupSettings,
    required this.onRepairStartupLaunchConfiguration,
    required this.onCopyStartupDiagnostic,
    required this.onCheckUpdates,
    required this.onCheckAutomaticUpdates,
    required this.onCopyUpdateDiagnostics,
    required this.onUpdateNotificationsChanged,
    required this.onAutomaticSilentUpdatesChanged,
    required this.onUseManualOnlyUpdateMode,
    this.pendingUpdateNotice,
    this.releaseNotes,
    this.releaseNotesUrl,
    this.updateCheckNotice,
  });

  final String appVersion;
  final bool isDarkThemeEnabled;
  final bool startWithWindows;
  final bool startMinimized;
  final bool minimizeToTray;
  final bool closeToTray;
  final String lastUpdateCheck;
  final String lastBackgroundUpdateCheck;
  final String lastAutomaticUpdateCheck;
  final String autoUpdateFeedStatus;
  final bool updateNotificationsEnabled;
  final bool automaticSilentUpdatesEnabled;
  final bool isCheckingUpdates;
  final bool isCheckingAutomaticUpdates;
  final bool startupSupported;
  final bool startMinimizedSupported;
  final bool trayBehaviorSupported;
  final SystemSettingsErrorState? startupError;
  final SystemSettingsErrorState? preferenceError;
  final SystemSettingsErrorState? themeError;
  final SystemSettingsNoticeState? startupNotice;
  final bool isAutoUpdateAvailable;
  final String? autoUpdateUnavailableMessage;
  final String? pendingUpdateNotice;
  final String? releaseNotes;
  final String? releaseNotesUrl;
  final UpdateCheckInlineNotice? updateCheckNotice;
  final ValueChanged<bool> onDarkThemeChanged;
  final ValueChanged<bool> onStartWithWindowsChanged;
  final ValueChanged<bool> onStartMinimizedChanged;
  final ValueChanged<bool> onMinimizeToTrayChanged;
  final ValueChanged<bool> onCloseToTrayChanged;
  final VoidCallback onOpenStartupSettings;
  final VoidCallback onRepairStartupLaunchConfiguration;
  final VoidCallback onCopyStartupDiagnostic;
  final VoidCallback onCheckUpdates;
  final VoidCallback onCheckAutomaticUpdates;
  final VoidCallback onCopyUpdateDiagnostics;
  final ValueChanged<bool> onUpdateNotificationsChanged;
  final ValueChanged<bool> onAutomaticSilentUpdatesChanged;
  final VoidCallback onUseManualOnlyUpdateMode;

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
          body: UpdatesAboutConfigSection(
            appVersion: widget.appVersion,
            lastUpdateCheck: widget.lastUpdateCheck,
            lastBackgroundUpdateCheck: widget.lastBackgroundUpdateCheck,
            lastAutomaticUpdateCheck: widget.lastAutomaticUpdateCheck,
            autoUpdateFeedStatus: widget.autoUpdateFeedStatus,
            updateNotificationsEnabled: widget.updateNotificationsEnabled,
            automaticSilentUpdatesEnabled: widget.automaticSilentUpdatesEnabled,
            isCheckingUpdates: widget.isCheckingUpdates,
            isCheckingAutomaticUpdates: widget.isCheckingAutomaticUpdates,
            isAutoUpdateAvailable: widget.isAutoUpdateAvailable,
            unavailableMessage: widget.autoUpdateUnavailableMessage,
            releaseNotes: widget.releaseNotes,
            releaseNotesUrl: widget.releaseNotesUrl,
            onCheckUpdates: widget.onCheckUpdates,
            onCheckAutomaticUpdates: widget.onCheckAutomaticUpdates,
            onCopyUpdateDiagnostics: widget.onCopyUpdateDiagnostics,
            onUpdateNotificationsChanged: widget.onUpdateNotificationsChanged,
            onAutomaticSilentUpdatesChanged: widget.onAutomaticSilentUpdatesChanged,
            onUseManualOnlyUpdateMode: widget.onUseManualOnlyUpdateMode,
            pendingUpdateNotice: widget.pendingUpdateNotice,
            updateCheckNotice: widget.updateCheckNotice,
          ),
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
