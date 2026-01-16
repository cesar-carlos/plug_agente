import 'package:result_dart/result_dart.dart';
import '../../domain/repositories/i_notification_service.dart';

class CancelAllNotifications {
  final INotificationService _notificationService;

  CancelAllNotifications(this._notificationService);

  Future<Result<void>> call() async {
    return await _notificationService.cancelAll();
  }
}
