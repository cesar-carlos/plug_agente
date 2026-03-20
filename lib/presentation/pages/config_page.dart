import 'package:fluent_ui/fluent_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/presentation/pages/config/widgets/general_config_section.dart';
import 'package:plug_agente/presentation/providers/system_settings_provider.dart';
import 'package:plug_agente/presentation/providers/theme_provider.dart';
import 'package:plug_agente/shared/widgets/common/feedback/settings_feedback.dart';
import 'package:provider/provider.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({
    super.key,
  });

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  String _lastUpdateCheck = AppStrings.configLastUpdateNever;
  String _appVersion = AppConstants.appVersion;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _appVersion = info.version);
    }
  }

  String _formatLastUpdateCheck(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _getUpdateUnavailableMessage() {
    final capabilities = getIt<RuntimeCapabilities>();
    return capabilities.supportsAutoUpdate ? AppStrings.gsAutoUpdateNotConfigured : AppStrings.gsAutoUpdateNotSupported;
  }

  String _formatTechnicalDetails(UpdateCheckDiagnostics? diagnostics) {
    if (diagnostics == null) {
      return 'Sem dados tecnicos para a verificacao atual.';
    }

    final lines = <String>[
      'Detalhes tecnicos',
      'Checado em: ${_formatLastUpdateCheck(diagnostics.checkedAt)}',
      'Feed configurado: ${diagnostics.configuredFeedUrl}',
      'Feed consultado: ${diagnostics.requestedFeedUrl}',
    ];

    if (diagnostics.remoteVersion != null && diagnostics.remoteVersion!.isNotEmpty) {
      lines.add(
        'Versao remota: ${diagnostics.remoteVersion}',
      );
    } else if (diagnostics.appcastProbeVersion != null && diagnostics.appcastProbeVersion!.isNotEmpty) {
      lines.add(
        'Versao remota: ${diagnostics.appcastProbeVersion}',
      );
    }

    if (diagnostics.errorMessage != null && diagnostics.errorMessage!.isNotEmpty) {
      lines.add(
        'Erro do updater: ${diagnostics.errorMessage}',
      );
    } else if (diagnostics.probeErrorMessage != null && diagnostics.probeErrorMessage!.isNotEmpty) {
      lines.add(
        'Erro ao ler appcast: ${diagnostics.probeErrorMessage}',
      );
    }

    return lines.join('\n');
  }

  Future<void> _checkUpdates() async {
    final orchestrator = getIt<IAutoUpdateOrchestrator>();
    if (!orchestrator.isAvailable) {
      SettingsFeedback.showError(
        context: context,
        title: AppStrings.gsSectionUpdates,
        message: _getUpdateUnavailableMessage(),
      );
      return;
    }

    setState(() {
      _lastUpdateCheck = AppStrings.configUpdatesChecking;
    });

    final result = await orchestrator.checkManual();

    if (!mounted) {
      return;
    }

    final checkedAt = _formatLastUpdateCheck(DateTime.now());
    setState(() {
      _lastUpdateCheck = '${AppStrings.configLastUpdatePrefix}$checkedAt';
    });

    result.fold(
      (isUpdateAvailable) {
        final message = isUpdateAvailable
            ? AppStrings.configUpdatesAvailable
            : '${AppStrings.configUpdatesNotAvailable}\nSe voce acabou de publicar uma nova versao, aguarde ate 5 minutos e tente novamente.';
        final technicalDetails = _formatTechnicalDetails(
          orchestrator.lastManualDiagnostics,
        );
        return SettingsFeedback.showInfo(
          context: context,
          title: AppStrings.gsSectionUpdates,
          message: '$message\n\n$technicalDetails',
        );
      },
      (failure) {
        final technicalDetails = _formatTechnicalDetails(
          orchestrator.lastManualDiagnostics,
        );
        return SettingsFeedback.showError(
          context: context,
          title: AppStrings.gsSectionUpdates,
          message: '${failure.toDisplayMessage()}\n\n$technicalDetails',
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final systemSettingsProvider = context.watch<SystemSettingsProvider>();
    final startupSupported = getIt.isRegistered<IStartupService>();
    final capabilities = getIt<RuntimeCapabilities>();
    final supportsAutoUpdate = capabilities.supportsAutoUpdate;

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          AppStrings.navSettings,
          style: context.sectionTitle,
        ),
      ),
      content: Padding(
        padding: AppLayout.pagePadding(context),
        child: AppLayout.centeredContent(
          child: GeneralConfigSection(
            appVersion: _appVersion,
            isDarkThemeEnabled: themeProvider.isDarkMode,
            startWithWindows: systemSettingsProvider.startWithWindows,
            startMinimized: systemSettingsProvider.startMinimized,
            minimizeToTray: systemSettingsProvider.minimizeToTray,
            closeToTray: systemSettingsProvider.closeToTray,
            lastUpdateCheck: _lastUpdateCheck,
            startupSupported: startupSupported,
            startupError: systemSettingsProvider.lastError,
            supportsAutoUpdate: supportsAutoUpdate,
            onDarkThemeChanged: themeProvider.setIsDarkMode,
            onStartWithWindowsChanged: systemSettingsProvider.setStartWithWindows,
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
