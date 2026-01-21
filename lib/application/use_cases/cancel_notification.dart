import 'package:result_dart/result_dart.dart';

import '../../domain/repositories/i_notification_service.dart';

class CancelNotification {
  final INotificationService _notificationService;

  CancelNotification(this._notificationService);

  Future<Result<void>> call(int id) async {
    return await _notificationService.cancel(id);
  }
}
