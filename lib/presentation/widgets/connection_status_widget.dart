import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:provider/provider.dart';

class ConnectionStatusWidget extends StatelessWidget {
  const ConnectionStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, connectionProvider, child) {
        final l10n = AppLocalizations.of(context)!;
        IconData icon;
        Color color;
        String statusText;

        switch (connectionProvider.status) {
          case ConnectionStatus.connected:
            icon = FluentIcons.check_mark;
            color = AppColors.success;
            statusText = l10n.connectionStatusConnected;
          case ConnectionStatus.connecting:
            icon = FluentIcons.sync;
            color = AppColors.warning;
            statusText = l10n.connectionStatusConnecting;
          case ConnectionStatus.error:
            icon = FluentIcons.error_badge;
            color = AppColors.error;
            statusText = l10n.connectionStatusError;
          default:
            icon = FluentIcons.circle_pause;
            color = AppColors.disabled;
            statusText = l10n.connectionStatusDisconnected;
        }

        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: FluentTheme.of(context).resources.subtleFillColorSecondary,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Text(
                statusText,
                style: context.bodyText.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                connectionProvider.isDbConnected
                    ? l10n.connectionStatusDbConnected
                    : l10n.connectionStatusDbDisconnected,
                style: context.bodyText.copyWith(
                  color: connectionProvider.isDbConnected ? AppColors.success : AppColors.disabled,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
