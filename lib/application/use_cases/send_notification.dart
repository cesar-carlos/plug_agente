import 'package:result_dart/result_dart.dart';
import '../../domain/repositories/i_notification_service.dart';

class SendNotification {
  final INotificationService _notificationService;

  SendNotification(this._notificationService);

  Future<Result<void>> call({
    required String title,
    required String body,
    String? payload,
  }) async {
    return await _notificationService.show(
      title: title,
      body: body,
      payload: payload,
    );
  }
}
