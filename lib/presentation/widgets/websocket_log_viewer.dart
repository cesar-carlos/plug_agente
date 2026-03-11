import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:provider/provider.dart';

class WebSocketLogViewer extends StatelessWidget {
  const WebSocketLogViewer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketLogProvider>(
      builder: (context, logProvider, child) {
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'WebSocket Messages',
                    style: context.sectionTitle,
                  ),
                  Row(
                    children: [
                      ToggleSwitch(
                        checked: logProvider.isEnabled,
                        onChanged: (value) => logProvider.setEnabled(value),
                        content: const Text('Enabled'),
                      ),
                      const SizedBox(width: 16),
                      Button(
                        child: Text(
                          'Clear',
                          style: context.bodyText,
                        ),
                        onPressed: () => logProvider.clearMessages(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: logProvider.messages.isEmpty
                    ? Center(
                        child: Text(
                          'No messages yet',
                          style: context.bodyMuted,
                        ),
                      )
                    : ListView.builder(
                        itemCount: logProvider.messages.length,
                        itemBuilder: (context, index) {
                          final message = logProvider.messages[index];
                          return _buildMessageItem(context, message);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageItem(BuildContext context, WebSocketMessage message) {
    final isSent = message.direction == 'SENT';
    final theme = FluentTheme.of(context);
    final color = isSent
        ? theme.accentColor
        : (theme.brightness == Brightness.dark ? Colors.white : Colors.black);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md - 4),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).cardColor,
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  message.direction,
                  style: context.bodyMuted.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                message.event,
                style: context.bodyText.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            message.formattedData,
            style: context.bodyMuted.copyWith(
              fontFamily: 'Consolas',
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
