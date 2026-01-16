import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../providers/connection_provider.dart';

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
            break;
          case ConnectionStatus.connecting:
            icon = FluentIcons.sync;
            color = AppColors.warning;
            statusText = 'Connecting...';
            break;
          case ConnectionStatus.error:
            icon = FluentIcons.error_badge;
            color = AppColors.error;
            statusText = 'Connection Error';
            break;
          default:
            icon = FluentIcons.circle_pause;
            color = AppColors.disabled;
            statusText = 'Disconnected';
        }

        return Padding(
          padding: const EdgeInsets.all(16.0),
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
