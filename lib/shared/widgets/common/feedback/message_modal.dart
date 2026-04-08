import 'package:fluent_ui/fluent_ui.dart';

import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';

enum MessageType { info, success, warning, error, confirmation }

class MessageModal extends StatelessWidget {
  const MessageModal({
    super.key,
    this.title,
    this.message,
    this.content,
    this.type = MessageType.info,
    this.onConfirm,
    this.onCancel,
    this.confirmText,
    this.cancelText,
  });
  final String? title;
  final String? message;
  final Widget? content;
  final MessageType type;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final String? confirmText;
  final String? cancelText;

  static Future<T?> show<T>({
    required BuildContext context,
    String? title,
    String? message,
    Widget? content,
    MessageType type = MessageType.info,
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
    String? confirmText,
    String? cancelText,
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) => MessageModal(
        title: title,
        message: message,
        content: content,
        type: type,
        onConfirm: onConfirm,
        onCancel: onCancel,
        confirmText: confirmText,
        cancelText: cancelText,
      ),
    );
  }

  static Future<T?> showInfo<T>({
    required BuildContext context,
    required String title,
    required String message,
    VoidCallback? onConfirm,
    String? confirmText,
  }) {
    return show<T>(
      context: context,
      title: title,
      message: message,
      onConfirm: onConfirm,
      confirmText: confirmText,
    );
  }

  static Future<T?> showSuccess<T>({
    required BuildContext context,
    required String title,
    required String message,
    VoidCallback? onConfirm,
    String? confirmText,
  }) {
    return show<T>(
      context: context,
      title: title,
      message: message,
      type: MessageType.success,
      onConfirm: onConfirm,
      confirmText: confirmText,
    );
  }

  static Future<T?> showError<T>({
    required BuildContext context,
    required String title,
    required String message,
    VoidCallback? onConfirm,
    String? confirmText,
  }) {
    return show<T>(
      context: context,
      title: title,
      message: message,
      type: MessageType.error,
      onConfirm: onConfirm,
      confirmText: confirmText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    AppFeedbackColors feedbackColors;
    IconData iconData;

    switch (type) {
      case MessageType.success:
        feedbackColors = colors.feedback(AppFeedbackTone.success);
        iconData = FluentIcons.completed_solid;
      case MessageType.warning:
        feedbackColors = colors.feedback(AppFeedbackTone.warning);
        iconData = FluentIcons.warning;
      case MessageType.error:
        feedbackColors = colors.feedback(AppFeedbackTone.error);
        iconData = FluentIcons.error_badge;
      case MessageType.confirmation:
        feedbackColors = colors.feedback(AppFeedbackTone.info);
        iconData = FluentIcons.help;
      case MessageType.info:
        feedbackColors = colors.feedback(AppFeedbackTone.info);
        iconData = FluentIcons.info;
    }

    return ContentDialog(
      title: Row(
        children: [
          Icon(iconData, color: feedbackColors.accent, size: 24),
          if (title != null) ...[
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                title!,
                style: context.sectionTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null)
              type == MessageType.error
                  ? SelectableText(
                      message!,
                      style: context.bodyText,
                    )
                  : Text(message!, style: context.bodyText),
            if (content != null) ...[
              if (message != null) const SizedBox(height: AppSpacing.md),
              content!,
            ],
          ],
        ),
      ),
      actions: _buildActions(context, feedbackColors),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    AppFeedbackColors feedbackColors,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final actions = <Widget>[];

    if (onCancel != null || type == MessageType.confirmation || cancelText != null) {
      actions.add(
        AppButton(
          label: cancelText ?? l10n.btnCancel,
          isPrimary: false,
          labelStyle: context.bodyText,
          onPressed: () {
            if (onCancel != null) {
              onCancel!();
            }
            Navigator.of(context).pop(false);
          },
        ),
      );
    }

    actions.add(
      AppButton(
        label: confirmText ?? l10n.btnOk,
        filledBackgroundColor: feedbackColors.accent,
        labelStyle: context.bodyText.copyWith(fontWeight: FontWeight.w600),
        onPressed: () {
          if (onConfirm != null) {
            onConfirm!();
          }
          Navigator.of(context).pop(true);
        },
      ),
    );

    return actions;
  }
}
