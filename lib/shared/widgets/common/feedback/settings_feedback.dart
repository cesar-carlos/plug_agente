import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';

class SettingsFeedback {
  const SettingsFeedback._();

  static Future<void> showInfo({
    required BuildContext context,
    required String title,
    required String message,
    VoidCallback? onConfirm,
  }) {
    return MessageModal.showInfo<void>(
      context: context,
      title: title,
      message: message,
      onConfirm: onConfirm,
    );
  }

  static Future<void> showSuccess({
    required BuildContext context,
    required String title,
    required String message,
    VoidCallback? onConfirm,
  }) {
    return MessageModal.showSuccess<void>(
      context: context,
      title: title,
      message: message,
      onConfirm: onConfirm,
    );
  }

  static Future<void> showError({
    required BuildContext context,
    required String title,
    required String message,
    VoidCallback? onConfirm,
  }) {
    return MessageModal.showError<void>(
      context: context,
      title: title,
      message: message,
      onConfirm: onConfirm,
    );
  }

  static Future<bool> showConfirmation({
    required BuildContext context,
    required String title,
    required String message,
    String? confirmText,
    String? cancelText,
  }) async {
    final result = await MessageModal.show<bool>(
      context: context,
      title: title,
      message: message,
      type: MessageType.confirmation,
      confirmText: confirmText,
      cancelText: cancelText,
    );
    return result ?? false;
  }
}
