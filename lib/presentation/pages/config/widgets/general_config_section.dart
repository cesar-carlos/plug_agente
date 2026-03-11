import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/theme/app_spacing.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return SingleChildScrollView(
      child: SettingsSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsSectionTitle(title: 'Aparência'),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: 'Tema escuro',
              value: isDarkThemeEnabled,
              onChanged: onDarkThemeChanged,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.lg),
            const SettingsSectionTitle(title: 'Sistema'),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: 'Iniciar com o Windows',
              value: startWithWindows,
              onChanged: onStartWithWindowsChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: 'Iniciar minimizado',
              value: startMinimized,
              onChanged: onStartMinimizedChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: 'Minimizar para bandeja',
              value: minimizeToTray,
              onChanged: onMinimizeToTrayChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsToggleTile(
              label: 'Fechar para bandeja',
              value: closeToTray,
              onChanged: onCloseToTrayChanged,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.lg),
            const SettingsSectionTitle(title: 'Atualizações'),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Verificar atualizações\n$lastUpdateCheck',
                    style: theme.typography.body,
                  ),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.refresh),
                  onPressed: onCheckUpdates,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.lg),
            const SettingsSectionTitle(title: 'Sobre'),
            const SizedBox(height: AppSpacing.md),
            const SettingsKeyValue(
              label: 'Versão',
              value: AppConstants.appVersion,
            ),
            const SizedBox(height: AppSpacing.md),
            const SettingsKeyValue(
              label: 'Licença',
              value: 'MIT License',
            ),
          ],
        ),
      ),
    );
  }
}
