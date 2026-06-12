import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';

class WebSocketLogMessageItem extends StatelessWidget {
  const WebSocketLogMessageItem({required this.message, super.key});

  final WebSocketMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final color = _resolveColor(context, message.direction);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md - 4),
      decoration: BoxDecoration(
        color: theme.cardColor,
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
              Expanded(
                child: Text(
                  message.event,
                  style: context.bodyText.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message.formattedData,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: context.bodyMuted.copyWith(
              fontFamily: 'Consolas',
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Color _resolveColor(BuildContext context, String direction) {
    final colors = context.appColors;
    if (direction == 'SENT') {
      return colors.brand;
    }
    if (direction == 'AUTH') {
      return colors.warning;
    }
    if (direction == 'SECURITY') {
      return colors.warning;
    }
    if (direction == 'PERFORMANCE') {
      return colors.warning;
    }
    if (direction == 'ERROR') {
      return colors.error;
    }

    return colors.textPrimary;
  }
}
