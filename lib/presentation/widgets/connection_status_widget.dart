import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/extensions/hub_recovery_ui_hint_l10n.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:provider/provider.dart';

class ConnectionStatusWidget extends StatelessWidget {
  const ConnectionStatusWidget({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer2<ConnectionProvider, AuthProvider>(
      builder: (context, connectionProvider, authProvider, child) {
        final colors = context.appColors;
        final IconData icon;
        final Color color;
        final String statusText;

        switch (connectionProvider.status) {
          case ConnectionStatus.connected:
            icon = FluentIcons.check_mark;
            color = colors.success;
            statusText = l10n.connectionStatusHubConnected;
          case ConnectionStatus.connecting:
            icon = FluentIcons.sync;
            color = colors.warning;
            statusText = l10n.connectionStatusHubConnecting;
          case ConnectionStatus.negotiating:
            icon = FluentIcons.sync;
            color = colors.warning;
            statusText = l10n.connectionStatusHubConnecting;
          case ConnectionStatus.reconnecting:
            icon = FluentIcons.sync;
            color = colors.warning;
            statusText = connectionProvider.hubRecoveryUiHint.connectionStatusLabel(l10n);
          case ConnectionStatus.error:
            icon = FluentIcons.error_badge;
            color = colors.error;
            statusText = l10n.connectionStatusHubError;
          case ConnectionStatus.disconnected:
            icon = FluentIcons.circle_pause;
            color = colors.disabled;
            statusText = l10n.connectionStatusHubDisconnected;
        }

        final sessionAuthError = authProvider.error.trim();
        final sessionText = _sessionLine(l10n, authProvider);
        final sessionColor = switch (authProvider.status) {
          AuthStatus.error => colors.error,
          AuthStatus.authenticated => colors.success,
          _ => colors.disabled,
        };
        final sessionTooltip = sessionAuthError.isNotEmpty ? sessionAuthError : sessionText;

        final dbShort = connectionProvider.isDbConnected
            ? l10n.connectionStatusDatabaseConnected
            : l10n.connectionStatusDatabaseDisconnected;

        final hubErrorTooltip = switch (connectionProvider.status) {
          ConnectionStatus.error => _hubErrorTooltip(connectionProvider, l10n),
          _ => null,
        };

        final iconSize = compact ? 14.0 : 16.0;
        final lineStyle = compact
            ? context.bodyText.copyWith(
                fontSize: 12,
                height: 1.2,
              )
            : context.bodyText;
        final sessionStyle = lineStyle.copyWith(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w500,
          color: sessionColor,
        );

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
            borderRadius: BorderRadius.circular(compact ? AppRadius.sm : AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: iconSize),
                  SizedBox(width: compact ? AppSpacing.xs : AppSpacing.sm),
                  Expanded(
                    child: Tooltip(
                      message: hubErrorTooltip ?? statusText,
                      child: Text(
                        statusText,
                        style: lineStyle.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: l10n.connectionStatusDatabaseTooltip,
                    child: Semantics(
                      label: '$dbShort. ${l10n.connectionStatusDatabaseTooltip}',
                      child: Text(
                        dbShort,
                        style: lineStyle.copyWith(
                          color: connectionProvider.isDbConnected ? colors.success : colors.disabled,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: EdgeInsets.only(left: iconSize + (compact ? AppSpacing.xs : AppSpacing.sm)),
                child: Tooltip(
                  message: sessionTooltip,
                  child: Text(sessionText, style: sessionStyle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _sessionLine(AppLocalizations l10n, AuthProvider authProvider) {
    if (authProvider.error.trim().isNotEmpty) {
      return l10n.connectionStatusSessionError;
    }
    if (authProvider.status == AuthStatus.authenticated) {
      return l10n.connectionStatusSessionAuthenticated;
    }
    return l10n.connectionStatusSessionUnauthenticated;
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
