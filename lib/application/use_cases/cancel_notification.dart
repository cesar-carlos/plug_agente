import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:result_dart/result_dart.dart';

class CancelNotification {
  CancelNotification(this._notificationService);
  final INotificationService _notificationService;

  Future<Result<void>> call(int id) async {
    return _notificationService.cancel(id);
  }
}
