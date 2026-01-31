import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:result_dart/result_dart.dart';

class ScheduleNotification {
  ScheduleNotification(this._notificationService);
  final INotificationService _notificationService;

  Future<Result<void>> call({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    return _notificationService.schedule(
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      payload: payload,
    );
  }
}
