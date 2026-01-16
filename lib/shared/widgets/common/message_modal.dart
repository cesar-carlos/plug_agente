import 'package:fluent_ui/fluent_ui.dart';
import '../../../core/theme/app_colors.dart';

enum MessageType { info, success, warning, error, confirmation }

class MessageModal extends StatelessWidget {
  final String? title;
  final String? message;
  final Widget? content;
  final MessageType type;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final String? confirmText;
  final String? cancelText;

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
        break;
      case MessageType.warning:
        accentColor = AppColors.warning;
        iconData = FluentIcons.warning;
        break;
      case MessageType.error:
        accentColor = AppColors.error;
        iconData = FluentIcons.error_badge;
        break;
      case MessageType.confirmation:
        accentColor = AppColors.primary;
        iconData = FluentIcons.help;
        break;
      case MessageType.info:
        accentColor = AppColors.primary;
        iconData = FluentIcons.info;
        break;
    }

    return ContentDialog(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, color: accentColor, size: 24),
          if (title != null) ...[const SizedBox(width: 12), Text(title!)],
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null) Text(message!, style: const TextStyle(fontSize: 16)),
            if (content != null) ...[if (message != null) const SizedBox(height: 12), content!],
          ],
        ),
      ),
      actions: _buildActions(context, accentColor),
    );
  }

  List<Widget> _buildActions(BuildContext context, Color accentColor) {
    final List<Widget> actions = [];

    // Botão Cancelar (apenas se fornecido callback ou texto, ou se for confirmação)
    if (onCancel != null || type == MessageType.confirmation || cancelText != null) {
      actions.add(
        Button(
          onPressed: () {
            if (onCancel != null) {
              onCancel!();
            }
            Navigator.of(context).pop(false); // Retorna false se for aguardado
          },
          child: Text(cancelText ?? 'Cancelar'),
        ),
      );
    }

    // Botão Confirmar/OK
    actions.add(
      FilledButton(
        style: ButtonStyle(backgroundColor: WidgetStateProperty.all(accentColor)),
        onPressed: () {
          if (onConfirm != null) {
            onConfirm!();
          }
          Navigator.of(context).pop(true); // Retorna true se for aguardado
        },
        child: Text(confirmText ?? 'OK'),
      ),
    );

    return actions;
  }
}
