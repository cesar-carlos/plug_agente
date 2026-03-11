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
  final String lastUpdateCheck;
  final ValueChanged<bool> onDarkThemeChanged;
  final ValueChanged<bool> onStartWithWindowsChanged;
  final ValueChanged<bool> onStartMinimizedChanged;
  final ValueChanged<bool> onMinimizeToTrayChanged;
  final ValueChanged<bool> onCloseToTrayChanged;
  final VoidCallback onCheckUpdates;
  final VoidCallback onOpenStartupSettings;
  final bool startupSupported;
  final String? startupError;

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

class _StartupErrorMessage extends StatelessWidget {
  const _StartupErrorMessage({
    required this.error,
    required this.onOpenSettings,
  });

  final String error;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_badge,
            color: Colors.red,
            size: 16,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              error,
              style: theme.typography.caption?.copyWith(
                color: Colors.red,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: onOpenSettings,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(
                Colors.red.withValues(alpha: 0.1),
              ),
              foregroundColor: WidgetStateProperty.all(Colors.red),
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
            ),
            child: const Text('Abrir configurações'),
          ),
        ],
      ),
    );
  }
}
