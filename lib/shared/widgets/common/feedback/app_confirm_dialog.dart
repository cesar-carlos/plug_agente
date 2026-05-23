import 'package:flutter/widgets.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';

/// Desktop confirmation dialog aligned with [MessageModal] (Fluent confirmation pattern).
class AppConfirmDialog {
  const AppConfirmDialog._();

  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
  }) async {
    final result = await MessageModal.show<bool>(
      context: context,
      title: title,
      message: message,
      type: MessageType.confirmation,
      confirmText: confirmLabel,
      cancelText: cancelLabel,
    );
    return result ?? false;
  }
}
