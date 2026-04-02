import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';

class InlineFeedbackCard extends StatelessWidget {
  const InlineFeedbackCard({
    required this.severity,
    super.key,
    this.title,
    this.message,
    this.content,
    this.onDismiss,
  }) : assert(
         message != null || content != null,
         'Provide a message or content for InlineFeedbackCard.',
       );

  final InfoBarSeverity severity;
  final String? title;
  final String? message;
  final Widget? content;
  final VoidCallback? onDismiss;

  AppFeedbackTone _tone() {
    return switch (severity) {
      InfoBarSeverity.success => AppFeedbackTone.success,
      InfoBarSeverity.warning => AppFeedbackTone.warning,
      InfoBarSeverity.error => AppFeedbackTone.error,
      InfoBarSeverity.info => AppFeedbackTone.info,
    };
  }

  IconData _icon() {
    return switch (severity) {
      InfoBarSeverity.success => FluentIcons.completed,
      InfoBarSeverity.warning => FluentIcons.warning,
      InfoBarSeverity.error => FluentIcons.error_badge,
      InfoBarSeverity.info => FluentIcons.info,
    };
  }

  @override
  Widget build(BuildContext context) {
    final feedbackColors = context.appColors.feedback(_tone());
    final bodyStyle = context.bodyText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: feedbackColors.background,
        border: Border.all(color: feedbackColors.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _icon(),
                size: 18,
                color: feedbackColors.accent,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: context.bodyStrong.copyWith(
                          color: feedbackColors.accent,
                        ),
                      ),
                    if (message != null)
                      SelectableText(
                        message!,
                        style: bodyStyle.copyWith(
                          color: severity == InfoBarSeverity.error ? feedbackColors.foreground : null,
                        ),
                      ),
                  ],
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  icon: const Icon(FluentIcons.clear, size: 14),
                  onPressed: onDismiss,
                ),
            ],
          ),
          if (content != null) ...[
            const SizedBox(height: AppSpacing.sm),
            content!,
          ],
        ],
      ),
    );
  }
}
