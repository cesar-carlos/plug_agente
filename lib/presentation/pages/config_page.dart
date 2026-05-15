import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/config/app_environment.dart';
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
import 'package:plug_agente/presentation/pages/config/widgets/backup_config_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/preferences_config_section.dart';
import 'package:plug_agente/presentation/pages/config/widgets/updates_about_config_section.dart';
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

  String _formatDurationMs(DateTime? startedAt, DateTime? completedAt) {
    if (startedAt == null || completedAt == null) {
      return '-';
    }
    return completedAt.difference(startedAt).inMilliseconds.toString();
  }

  String _formatCompletionSource(
    AppLocalizations l10n,
    UpdateCheckCompletionSource? source,
  ) {
    return switch (source) {
      UpdateCheckCompletionSource.updateAvailable => l10n.configUpdateCompletionSourceUpdateAvailable,
      UpdateCheckCompletionSource.updateNotAvailable => l10n.configUpdateCompletionSourceUpdateNotAvailable,
      UpdateCheckCompletionSource.updaterError => l10n.configUpdateCompletionSourceUpdaterError,
      UpdateCheckCompletionSource.triggerTimeout => l10n.configUpdateCompletionSourceTriggerTimeout,
      UpdateCheckCompletionSource.completionTimeout => l10n.configUpdateCompletionSourceCompletionTimeout,
      UpdateCheckCompletionSource.triggerFailure => l10n.configUpdateCompletionSourceTriggerFailure,
      UpdateCheckCompletionSource.notInitialized => l10n.configUpdateCompletionSourceNotInitialized,
      UpdateCheckCompletionSource.circuitOpen => l10n.configUpdateCompletionSourceCircuitOpen,
      UpdateCheckCompletionSource.automaticDisabled => l10n.configUpdateCompletionSourceAutomaticDisabled,
      UpdateCheckCompletionSource.automaticPendingCompleted =>
        l10n.configUpdateCompletionSourceAutomaticPendingCompleted,
      UpdateCheckCompletionSource.automaticPendingFailed => l10n.configUpdateCompletionSourceAutomaticPendingFailed,
      UpdateCheckCompletionSource.automaticUpdateNotAvailable =>
        l10n.configUpdateCompletionSourceAutomaticUpdateNotAvailable,
      UpdateCheckCompletionSource.automaticValidationFailure =>
        l10n.configUpdateCompletionSourceAutomaticValidationFailure,
      UpdateCheckCompletionSource.automaticDownloadFailure => l10n.configUpdateCompletionSourceAutomaticDownloadFailure,
      UpdateCheckCompletionSource.automaticInstallStarted => l10n.configUpdateCompletionSourceAutomaticInstallStarted,
      UpdateCheckCompletionSource.automaticInstallFailure => l10n.configUpdateCompletionSourceAutomaticInstallFailure,
      UpdateCheckCompletionSource.automaticCooldown => l10n.configUpdateCompletionSourceAutomaticCooldown,
      UpdateCheckCompletionSource.automaticRolloutSkipped => l10n.configUpdateCompletionSourceAutomaticRolloutSkipped,
      null => '-',
    };
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
        : ' - ${_formatCompletionSource(l10n, diagnostics.completionSource)}';
    return '${l10n.configLastBackgroundUpdatePrefix}$checkedAt$completion';
  }

  String _buildAutomaticUpdateLabel(
    AppLocalizations l10n,
    UpdateCheckDiagnostics? diagnostics,
  ) {
    if (diagnostics == null) {
      return '';
    }

    final checkedAt = _formatLastUpdateCheck(diagnostics.checkedAt);
    final completion = diagnostics.completionSource == null
        ? ''
        : ' - ${_formatCompletionSource(l10n, diagnostics.completionSource)}';
    return '${l10n.configLastAutomaticUpdatePrefix}$checkedAt$completion';
  }

  String _formatTechnicalDetails(
    AppLocalizations l10n,
    UpdateCheckDiagnostics? manualDiagnostics,
    UpdateCheckDiagnostics? backgroundDiagnostics,
    UpdateCheckDiagnostics? automaticDiagnostics,
  ) {
    if (manualDiagnostics == null && backgroundDiagnostics == null && automaticDiagnostics == null) {
      return l10n.configUpdateTechnicalNoData;
    }

    final lines = <String>[];
    if (manualDiagnostics != null) {
      _appendDiagnosticsSection(
        lines,
        l10n: l10n,
        title: l10n.configUpdateTechnicalTitle,
        diagnostics: manualDiagnostics,
      );
    }
    if (backgroundDiagnostics != null) {
      if (lines.isNotEmpty) {
        lines.add('');
      }
      _appendDiagnosticsSection(
        lines,
        l10n: l10n,
        title: l10n.configUpdateTechnicalBackgroundTitle,
        diagnostics: backgroundDiagnostics,
      );
    }
    if (automaticDiagnostics != null) {
      if (lines.isNotEmpty) {
        lines.add('');
      }
      _appendDiagnosticsSection(
        lines,
        l10n: l10n,
        title: l10n.configUpdateTechnicalAutomaticTitle,
        diagnostics: automaticDiagnostics,
      );
    }

    return lines.join('\n');
  }

  String _buildUpdateSupportDiagnostics(
    AppLocalizations l10n,
    IAutoUpdateOrchestrator orchestrator,
  ) {
    final manual = orchestrator.lastManualDiagnostics;
    final background = orchestrator.lastBackgroundDiagnostics;
    final automatic = orchestrator.lastAutomaticDiagnostics;
    final technicalDetails = _formatTechnicalDetails(
      l10n,
      manual,
      background,
      automatic,
    );
    return <String>[
      'Plug Agente Auto-Update',
      '${l10n.gsLabelVersion}: $_appVersion',
      '',
      technicalDetails,
    ].join('\n');
  }

  void _appendDiagnosticsSection(
    List<String> lines, {
    required AppLocalizations l10n,
    required String title,
    required UpdateCheckDiagnostics diagnostics,
  }) {
    lines.add(title);
    lines.addAll(<String>[
      '${l10n.configUpdateTechnicalCurrentVersion}: ${diagnostics.currentVersion ?? _appVersion}',
      '${l10n.configUpdateTechnicalCheckedAt}: ${_formatLastUpdateCheck(diagnostics.checkedAt)}',
      '${l10n.configUpdateTechnicalConfiguredFeed}: ${diagnostics.configuredFeedUrl}',
      '${l10n.configUpdateTechnicalRequestedFeed}: ${diagnostics.requestedFeedUrl}',
      '${l10n.configUpdateTechnicalOfficialFeed}: ${isOfficialAutoUpdateFeedUrl(diagnostics.configuredFeedUrl) ? l10n.configUpdateTechnicalOfficialFeedYes : l10n.configUpdateTechnicalOfficialFeedNo}',
      '${l10n.configUpdateTechnicalProbeRequestUrl}: ${diagnostics.probeRequestUrl ?? diagnostics.requestedFeedUrl}',
      '${l10n.configUpdateTechnicalProbeSucceeded}: ${diagnostics.probeSucceeded == null
          ? '-'
          : diagnostics.probeSucceeded!
          ? l10n.configUpdateTechnicalOfficialFeedYes
          : l10n.configUpdateTechnicalOfficialFeedNo}',
      '${l10n.configUpdateTechnicalCompletionSource}: ${_formatCompletionSource(l10n, diagnostics.completionSource)}',
      '${l10n.configUpdateTechnicalTriggerDurationMs}: ${_formatDurationMs(diagnostics.triggerStartedAt, diagnostics.triggerCompletedAt)}',
      '${l10n.configUpdateTechnicalTotalDurationMs}: ${_formatDurationMs(diagnostics.checkedAt, diagnostics.completedAt)}',
    ]);

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

    if (diagnostics.assetName != null && diagnostics.assetName!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalAssetName}: ${diagnostics.assetName}');
    }
    if (diagnostics.assetUrl != null && diagnostics.assetUrl!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalAssetUrl}: ${diagnostics.assetUrl}');
    }
    if (diagnostics.assetSize != null) {
      lines.add('${l10n.configUpdateTechnicalAssetSize}: ${diagnostics.assetSize}');
    }
    if (diagnostics.sha256 != null && diagnostics.sha256!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalSha256}: ${diagnostics.sha256}');
    }
    if (diagnostics.actualSha256 != null && diagnostics.actualSha256!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalActualSha256}: ${diagnostics.actualSha256}');
    }
    if (diagnostics.hashValidationStatus != null && diagnostics.hashValidationStatus!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalHashValidationStatus}: ${diagnostics.hashValidationStatus}');
    }
    if (diagnostics.rolloutChannel != null && diagnostics.rolloutChannel!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalRolloutChannel}: ${diagnostics.rolloutChannel}');
    }
    if (diagnostics.rolloutPercentage != null) {
      lines.add('${l10n.configUpdateTechnicalRolloutPercentage}: ${diagnostics.rolloutPercentage}');
    }
    if (diagnostics.rolloutBucket != null) {
      lines.add('${l10n.configUpdateTechnicalRolloutBucket}: ${diagnostics.rolloutBucket}');
    }
    if (diagnostics.rolloutEligible != null) {
      lines.add(
        '${l10n.configUpdateTechnicalRolloutEligible}: ${diagnostics.rolloutEligible! ? l10n.configUpdateTechnicalOfficialFeedYes : l10n.configUpdateTechnicalOfficialFeedNo}',
      );
    }
    if (diagnostics.pendingVersion != null && diagnostics.pendingVersion!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalPendingVersion}: ${diagnostics.pendingVersion}');
    }
    if (diagnostics.installerPath != null && diagnostics.installerPath!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalInstallerPath}: ${diagnostics.installerPath}');
    }
    if (diagnostics.installerLogPath != null && diagnostics.installerLogPath!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalInstallerLogPath}: ${diagnostics.installerLogPath}');
    }
    if (diagnostics.installDirectory != null && diagnostics.installDirectory!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalInstallDirectory}: ${diagnostics.installDirectory}');
    }
    if (diagnostics.updateDirectorySecurityStatus != null && diagnostics.updateDirectorySecurityStatus!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalUpdateDirectorySecurity}: ${diagnostics.updateDirectorySecurityStatus}');
    }
    if (diagnostics.installDirectoryWritable != null) {
      lines.add(
        '${l10n.configUpdateTechnicalInstallDirectoryWritable}: ${diagnostics.installDirectoryWritable! ? l10n.configUpdateTechnicalOfficialFeedYes : l10n.configUpdateTechnicalOfficialFeedNo}',
      );
    }
    if (diagnostics.silentUpdateStrategy != null && diagnostics.silentUpdateStrategy!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalSilentStrategy}: ${diagnostics.silentUpdateStrategy}');
    }
    if (diagnostics.launcherPath != null && diagnostics.launcherPath!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalLauncherPath}: ${diagnostics.launcherPath}');
    }
    if (diagnostics.launcherStatusPath != null && diagnostics.launcherStatusPath!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalLauncherStatusPath}: ${diagnostics.launcherStatusPath}');
    }
    if (diagnostics.launcherState != null && diagnostics.launcherState!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalLauncherState}: ${diagnostics.launcherState}');
    }
    if (diagnostics.appPid != null) {
      lines.add('${l10n.configUpdateTechnicalAppPid}: ${diagnostics.appPid}');
    }
    if (diagnostics.signatureStatus != null && diagnostics.signatureStatus!.isNotEmpty) {
      lines.add('${l10n.configUpdateTechnicalSignatureStatus}: ${diagnostics.signatureStatus}');
    }
    if (diagnostics.signatureRequired != null) {
      lines.add(
        '${l10n.configUpdateTechnicalSignatureRequired}: ${diagnostics.signatureRequired! ? l10n.configUpdateTechnicalOfficialFeedYes : l10n.configUpdateTechnicalOfficialFeedNo}',
      );
    }
    if (diagnostics.waitForAppExitDurationMs != null) {
      lines.add(
        '${l10n.configUpdateTechnicalWaitForAppExitDurationMs}: ${diagnostics.waitForAppExitDurationMs}',
      );
    }
    if (diagnostics.nonAdminExitCode != null) {
      lines.add('${l10n.configUpdateTechnicalNonAdminExitCode}: ${diagnostics.nonAdminExitCode}');
    }
    if (diagnostics.nonAdminDurationMs != null) {
      lines.add('${l10n.configUpdateTechnicalNonAdminDurationMs}: ${diagnostics.nonAdminDurationMs}');
    }
    if (diagnostics.elevatedExitCode != null) {
      lines.add('${l10n.configUpdateTechnicalElevatedExitCode}: ${diagnostics.elevatedExitCode}');
    }
    if (diagnostics.elevatedDurationMs != null) {
      lines.add('${l10n.configUpdateTechnicalElevatedDurationMs}: ${diagnostics.elevatedDurationMs}');
    }
    if (diagnostics.elevatedRetryStarted != null) {
      lines.add(
        '${l10n.configUpdateTechnicalElevatedRetryStarted}: ${diagnostics.elevatedRetryStarted! ? l10n.configUpdateTechnicalOfficialFeedYes : l10n.configUpdateTechnicalOfficialFeedNo}',
      );
    }
    if (diagnostics.elevatedCancelled != null) {
      lines.add(
        '${l10n.configUpdateTechnicalElevatedCancelled}: ${diagnostics.elevatedCancelled! ? l10n.configUpdateTechnicalOfficialFeedYes : l10n.configUpdateTechnicalOfficialFeedNo}',
      );
    }
    if (diagnostics.automaticFailureCount != null) {
      lines.add('${l10n.configUpdateTechnicalAutomaticFailureCount}: ${diagnostics.automaticFailureCount}');
    }
    if (diagnostics.automaticCooldownUntil != null) {
      lines.add(
        '${l10n.configUpdateTechnicalAutomaticCooldownUntil}: ${_formatLastUpdateCheck(diagnostics.automaticCooldownUntil!)}',
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
          null,
          null,
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
          null,
          null,
        );
        return SettingsFeedback.showError(
          context: context,
          title: l10n.gsSectionUpdates,
          message: '${failure.toDisplayMessage()}\n\n$technicalDetails',
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

  Future<void> _onAutomaticSilentUpdatesChanged(bool value) async {
    final l10n = AppLocalizations.of(context)!;
    final orchestrator = getIt<IAutoUpdateOrchestrator>();
    final result = await orchestrator.setAutomaticSilentUpdatesEnabled(value);
    if (!mounted) {
      return;
    }

    result.fold(
      (_) {
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
    final autoUpdateUnavailableMessage = isAutoUpdateAvailable ? null : _getUpdateUnavailableMessage(l10n);

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
            lastUpdateCheck: lastUpdateLabel,
            lastBackgroundUpdateCheck: lastBackgroundUpdateLabel,
            lastAutomaticUpdateCheck: lastAutomaticUpdateLabel,
            automaticSilentUpdatesEnabled: orchestrator.automaticSilentUpdatesEnabled,
            isCheckingUpdates: _isCheckingUpdates,
            startupSupported: startupSupported,
            startMinimizedSupported: capabilities.supportsTray,
            startupError: systemSettingsProvider.startupError,
            preferenceError: systemSettingsProvider.preferenceError,
            startupNotice: systemSettingsProvider.startupNotice,
            isAutoUpdateAvailable: isAutoUpdateAvailable,
            autoUpdateUnavailableMessage: autoUpdateUnavailableMessage,
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
            onCheckUpdates: _checkUpdates,
            onCopyUpdateDiagnostics: _copyUpdateDiagnostics,
            onAutomaticSilentUpdatesChanged: (value) {
              unawaited(_onAutomaticSilentUpdatesChanged(value));
            },
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
    required this.automaticSilentUpdatesEnabled,
    required this.isCheckingUpdates,
    required this.startupSupported,
    required this.startMinimizedSupported,
    required this.startupError,
    required this.preferenceError,
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
    required this.onCheckUpdates,
    required this.onCopyUpdateDiagnostics,
    required this.onAutomaticSilentUpdatesChanged,
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
  final bool automaticSilentUpdatesEnabled;
  final bool isCheckingUpdates;
  final bool startupSupported;
  final bool startMinimizedSupported;
  final SystemSettingsErrorState? startupError;
  final SystemSettingsErrorState? preferenceError;
  final SystemSettingsNoticeState? startupNotice;
  final bool isAutoUpdateAvailable;
  final String? autoUpdateUnavailableMessage;
  final ValueChanged<bool> onDarkThemeChanged;
  final ValueChanged<bool> onStartWithWindowsChanged;
  final ValueChanged<bool> onStartMinimizedChanged;
  final ValueChanged<bool> onMinimizeToTrayChanged;
  final ValueChanged<bool> onCloseToTrayChanged;
  final VoidCallback onOpenStartupSettings;
  final VoidCallback onRepairStartupLaunchConfiguration;
  final VoidCallback onCheckUpdates;
  final VoidCallback onCopyUpdateDiagnostics;
  final ValueChanged<bool> onAutomaticSilentUpdatesChanged;

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
            startupError: widget.startupError,
            preferenceError: widget.preferenceError,
            startupNotice: widget.startupNotice,
            onDarkThemeChanged: widget.onDarkThemeChanged,
            onStartWithWindowsChanged: widget.onStartWithWindowsChanged,
            onStartMinimizedChanged: widget.onStartMinimizedChanged,
            onMinimizeToTrayChanged: widget.onMinimizeToTrayChanged,
            onCloseToTrayChanged: widget.onCloseToTrayChanged,
            onOpenStartupSettings: widget.onOpenStartupSettings,
            onRepairStartupLaunchConfiguration: widget.onRepairStartupLaunchConfiguration,
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
            automaticSilentUpdatesEnabled: widget.automaticSilentUpdatesEnabled,
            isCheckingUpdates: widget.isCheckingUpdates,
            isAutoUpdateAvailable: widget.isAutoUpdateAvailable,
            unavailableMessage: widget.autoUpdateUnavailableMessage,
            onCheckUpdates: widget.onCheckUpdates,
            onCopyUpdateDiagnostics: widget.onCopyUpdateDiagnostics,
            onAutomaticSilentUpdatesChanged: widget.onAutomaticSilentUpdatesChanged,
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
