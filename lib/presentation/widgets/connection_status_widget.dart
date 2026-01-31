import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/app_colors.dart';
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

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: TextStyle(color: color, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text(
                connectionProvider.isDbConnected
                    ? 'DB: Connected'
                    : 'DB: Disconnected',
                style: TextStyle(
                  color: connectionProvider.isDbConnected
                      ? AppColors.success
                      : AppColors.disabled,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
