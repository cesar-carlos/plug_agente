import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/authorization_metrics_summary.dart';
import 'package:plug_agente/domain/entities/protocol_metrics_summary.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:plug_agente/presentation/widgets/websocket_log/websocket_log_message_item.dart';
import 'package:plug_agente/presentation/widgets/websocket_log_metrics_summary_cards.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:provider/provider.dart';

class WebSocketLogMessageListPane extends StatelessWidget {
  const WebSocketLogMessageListPane({
    required this.l10n,
    required this.authSummary,
    required this.protocolSummary,
    required this.deprecationCount,
    super.key,
  });

  final AppLocalizations l10n;
  final AuthorizationMetricsSummary? authSummary;
  final ProtocolMetricsSummary? protocolSummary;
  final int? deprecationCount;

  @override
  Widget build(BuildContext context) {
    final protocol = protocolSummary;
    final deprecations = deprecationCount;
    final logProvider = context.read<WebSocketLogProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Selector<WebSocketLogProvider, bool>(
                selector: (_, WebSocketLogProvider provider) => provider.isEnabled,
                builder: (BuildContext context, bool isEnabled, Widget? child) {
                  return Tooltip(
                    message: l10n.wsLogToggleEnabledTooltip,
                    child: ToggleSwitch(
                      checked: isEnabled,
                      onChanged: logProvider.setEnabled,
                      content: Text(l10n.wsLogEnabled),
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
              Tooltip(
                message: l10n.wsLogClearTooltip,
                child: AppButton(
                  label: l10n.wsLogClear,
                  isPrimary: false,
                  labelStyle: context.bodyText,
                  onPressed: logProvider.clearMessages,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              WebSocketLogAuthorizationSummaryCard(l10n: l10n, summary: authSummary),
              if (protocol != null && protocol.totalMessages > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                WebSocketLogProtocolMetricsSummaryCard(summary: protocol),
              ],
              if (deprecations != null) ...[
                const SizedBox(height: AppSpacing.sm),
                WebSocketLogDeprecationSummaryCard(
                  l10n: l10n,
                  count: deprecations,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: ListenableBuilder(
            listenable: logProvider,
            builder: (BuildContext context, Widget? child) {
              final messages = logProvider.messages;
              if (messages.isEmpty) {
                return Center(
                  child: Text(
                    l10n.wsLogNoMessages,
                    style: context.bodyMuted,
                  ),
                );
              }
              final visibleCount = messages.length.clamp(
                0,
                AppConstants.dashboardDiagnosticFeedMaxVisibleItems,
              );
              return ListView.builder(
                itemCount: visibleCount,
                itemBuilder: (BuildContext context, int index) {
                  return RepaintBoundary(
                    child: WebSocketLogMessageItem(message: messages[index]),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
