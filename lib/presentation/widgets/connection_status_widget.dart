import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:provider/provider.dart';

class ConnectionStatusWidget extends StatelessWidget {
  const ConnectionStatusWidget({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<ConnectionProvider>(
      builder: (context, connectionProvider, child) {
        final colors = context.appColors;
        IconData icon;
        Color color;
        String statusText;

        switch (connectionProvider.status) {
          case ConnectionStatus.connected:
            icon = FluentIcons.check_mark;
            color = colors.success;
            statusText = l10n.connectionStatusHubConnected;
          case ConnectionStatus.connecting:
            icon = FluentIcons.sync;
            color = colors.warning;
            statusText = l10n.connectionStatusHubConnecting;
          case ConnectionStatus.reconnecting:
            icon = FluentIcons.sync;
            color = colors.warning;
            statusText = l10n.connectionStatusHubReconnecting;
          case ConnectionStatus.error:
            icon = FluentIcons.error_badge;
            color = colors.error;
            statusText = l10n.connectionStatusHubError;
          case ConnectionStatus.disconnected:
            icon = FluentIcons.circle_pause;
            color = colors.disabled;
            statusText = l10n.connectionStatusHubDisconnected;
        }

        final dbShort = connectionProvider.isDbConnected
            ? l10n.connectionStatusDatabaseConnected
            : l10n.connectionStatusDatabaseDisconnected;

        final hubErrorTooltip = switch (connectionProvider.status) {
          ConnectionStatus.error => _hubErrorTooltip(connectionProvider, l10n),
          _ => null,
        };

        return Container(
          padding: compact
              ? const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                )
              : const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
          decoration: BoxDecoration(
            color: FluentTheme.of(context).resources.subtleFillColorSecondary,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Tooltip(
                message: hubErrorTooltip ?? statusText,
                child: Text(
                  statusText,
                  style: context.bodyText.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Tooltip(
                message: l10n.connectionStatusDatabaseTooltip,
                child: Semantics(
                  label: '$dbShort. ${l10n.connectionStatusDatabaseTooltip}',
                  child: Text(
                    dbShort,
                    style: context.bodyText.copyWith(
                      color: connectionProvider.isDbConnected ? colors.success : colors.disabled,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _hubErrorTooltip(
    ConnectionProvider connectionProvider,
    AppLocalizations l10n,
  ) {
    final raw = connectionProvider.error.trim();
    if (raw.isEmpty) {
      return l10n.connectionStatusHubError;
    }
    if (raw == ConnectionConstants.hubPersistentRetryExhaustedMessage) {
      return l10n.msgHubPersistentRetryExhausted;
    }
    return raw;
  }
}
