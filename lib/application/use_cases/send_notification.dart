import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:result_dart/result_dart.dart';

class SendNotification {
  SendNotification(this._notificationService);
  final INotificationService _notificationService;

  Future<Result<void>> call({
    required String title,
    required String body,
    String? payload,
  }) async {
    return _notificationService.show(
      title: title,
      body: body,
      payload: payload,
    );
  }
}
