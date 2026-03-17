import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/theme/theme.dart';
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

  @override
  void initState() {
    super.initState();
  }

  void _checkUpdates() {
    SettingsFeedback.showInfo(
      context: context,
      title: AppStrings.gsSectionUpdates,
      message: AppStrings.configUpdatesNotImplemented,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final systemSettingsProvider = context.watch<SystemSettingsProvider>();
    final startupSupported = getIt.isRegistered<IStartupService>();

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
            isDarkThemeEnabled: themeProvider.isDarkMode,
            startWithWindows: systemSettingsProvider.startWithWindows,
            startMinimized: systemSettingsProvider.startMinimized,
            minimizeToTray: systemSettingsProvider.minimizeToTray,
            closeToTray: systemSettingsProvider.closeToTray,
            lastUpdateCheck: _lastUpdateCheck,
            startupSupported: startupSupported,
            startupError: systemSettingsProvider.lastError,
            onDarkThemeChanged: themeProvider.setIsDarkMode,
            onStartWithWindowsChanged:
                systemSettingsProvider.setStartWithWindows,
            onStartMinimizedChanged: systemSettingsProvider.setStartMinimized,
            onMinimizeToTrayChanged: systemSettingsProvider.setMinimizeToTray,
            onCloseToTrayChanged: systemSettingsProvider.setCloseToTray,
            onOpenStartupSettings: systemSettingsProvider.openStartupSettings,
            onCheckUpdates: () {
              setState(
                () => _lastUpdateCheck = AppStrings.configLastUpdateManual,
              );
              _checkUpdates();
            },
          ),
        ),
      ),
    );
  }
}
