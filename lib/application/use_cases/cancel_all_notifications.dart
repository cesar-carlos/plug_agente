import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:result_dart/result_dart.dart';

class CancelAllNotifications {
  CancelAllNotifications(this._notificationService);
  final INotificationService _notificationService;

  Future<Result<void>> call() async {
    return _notificationService.cancelAll();
  }
}
