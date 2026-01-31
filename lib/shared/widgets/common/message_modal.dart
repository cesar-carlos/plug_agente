import 'package:fluent_ui/fluent_ui.dart';

import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/theme/app_colors.dart';

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

  @override
  Widget build(BuildContext context) {
    // Definir cores e ícones baseados no tipo
    Color accentColor;
    IconData iconData;

    switch (type) {
      case MessageType.success:
        accentColor = AppColors.success;
        iconData = FluentIcons.completed_solid;
      case MessageType.warning:
        accentColor = AppColors.warning;
        iconData = FluentIcons.warning;
      case MessageType.error:
        accentColor = AppColors.error;
        iconData = FluentIcons.error_badge;
      case MessageType.confirmation:
        accentColor = AppColors.primary;
        iconData = FluentIcons.help;
      case MessageType.info:
        accentColor = AppColors.primary;
        iconData = FluentIcons.info;
    }

    return ContentDialog(
      title: Row(
        children: [
          Icon(iconData, color: accentColor, size: 24),
          if (title != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title!,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
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
              Text(message!, style: const TextStyle(fontSize: 16)),
            if (content != null) ...[
              if (message != null) const SizedBox(height: 12),
              content!,
            ],
          ],
        ),
      ),
      actions: _buildActions(context, accentColor),
    );
  }

  List<Widget> _buildActions(BuildContext context, Color accentColor) {
    final actions = <Widget>[];

    // Botão Cancelar (apenas se fornecido callback ou texto, ou se for confirmação)
    if (onCancel != null ||
        type == MessageType.confirmation ||
        cancelText != null) {
      actions.add(
        Button(
          onPressed: () {
            if (onCancel != null) {
              onCancel!();
            }
            Navigator.of(context).pop(false); // Retorna false se for aguardado
          },
          child: Text(cancelText ?? AppStrings.btnCancel),
        ),
      );
    }

    // Botão Confirmar/OK
    actions.add(
      FilledButton(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(accentColor),
        ),
        onPressed: () {
          if (onConfirm != null) {
            onConfirm!();
          }
          Navigator.of(context).pop(true); // Retorna true se for aguardado
        },
        child: Text(confirmText ?? AppStrings.btnOk),
      ),
    );

    return actions;
  }
}
