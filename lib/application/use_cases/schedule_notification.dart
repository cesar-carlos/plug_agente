import 'package:result_dart/result_dart.dart';

import '../../domain/repositories/i_notification_service.dart';

class ScheduleNotification {
  final INotificationService _notificationService;

  ScheduleNotification(this._notificationService);

  Future<Result<void>> call({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    return await _notificationService.schedule(
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      payload: payload,
    );
  }
}
