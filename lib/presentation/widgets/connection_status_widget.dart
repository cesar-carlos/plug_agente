import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:provider/provider.dart';

class ConnectionStatusWidget extends StatelessWidget {
  const ConnectionStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, connectionProvider, child) {
        IconData icon;
        Color color;
        String statusText;

        switch (connectionProvider.status) {
          case ConnectionStatus.connected:
            icon = FluentIcons.check_mark;
            color = AppColors.success;
            statusText = 'Connected';
          case ConnectionStatus.connecting:
            icon = FluentIcons.sync;
            color = AppColors.warning;
            statusText = 'Connecting...';
          case ConnectionStatus.error:
            icon = FluentIcons.error_badge;
            color = AppColors.error;
            statusText = 'Connection Error';
          default:
            icon = FluentIcons.circle_pause;
            color = AppColors.disabled;
            statusText = 'Disconnected';
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
                connectionProvider.isDbConnected ? 'DB: Connected' : 'DB: Disconnected',
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
