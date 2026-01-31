import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:plug_agente/shared/widgets/common/app_card.dart';
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
                    style: FluentTheme.of(context).typography.subtitle,
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
                        child: const Text('Clear'),
                        onPressed: () => logProvider.clearMessages(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: logProvider.messages.isEmpty
                    ? Center(
                        child: Text(
                          'No messages yet',
                          style: FluentTheme.of(context).typography.body,
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).cardColor,
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  message.direction,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                message.event,
                style: FluentTheme.of(context).typography.bodyStrong,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            message.formattedData,
            style: FluentTheme.of(context).typography.caption?.copyWith(
              fontFamily: 'Consolas',
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
