import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/use_cases/cancel_all_notifications.dart';
import 'package:plug_agente/application/use_cases/cancel_notification.dart';
import 'package:plug_agente/application/use_cases/schedule_notification.dart';
import 'package:plug_agente/application/use_cases/send_notification.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:result_dart/result_dart.dart';

class NotificationProvider extends ChangeNotifier {
  NotificationProvider(
    this._sendNotification,
    this._scheduleNotification,
    this._cancelNotification,
    this._cancelAllNotifications,
  );
  final SendNotification _sendNotification;
  final ScheduleNotification _scheduleNotification;
  final CancelNotification _cancelNotification;
  final CancelAllNotifications _cancelAllNotifications;

  int _pendingOperations = 0;
  String? _error;
  bool _disposed = false;

  bool get isLoading => _pendingOperations > 0;
  String? get error => _error;

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) {
    return _runNotificationOperation(
      logPrefix: 'Failed to send notification',
      operation: () => _sendNotification(
        title: title,
        body: body,
        payload: payload,
      ),
    );
  }

  Future<void> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) {
    return _runNotificationOperation(
      logPrefix: 'Failed to schedule notification',
      operation: () => _scheduleNotification(
        title: title,
        body: body,
        scheduledTime: scheduledTime,
        payload: payload,
      ),
    );
  }

  Future<void> cancelNotification(int id) {
    return _runNotificationOperation(
      logPrefix: 'Failed to cancel notification',
      operation: () => _cancelNotification(id),
    );
  }

  Future<void> cancelAllNotifications() {
    return _runNotificationOperation(
      logPrefix: 'Failed to cancel all notifications',
      operation: _cancelAllNotifications.call,
    );
  }

  void clearError() {
    if (_disposed) {
      return;
    }
    _error = null;
    _notifyIfActive();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _beginOperation() {
    _error = null;
    _pendingOperations++;
    _notifyIfActive();
  }

  void _endOperation() {
    _pendingOperations--;
    if (_pendingOperations < 0) {
      _pendingOperations = 0;
    }
    _notifyIfActive();
  }

  void _notifyIfActive() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  Future<void> _runNotificationOperation({
    required Future<Result<void>> Function() operation,
    required String logPrefix,
  }) async {
    _beginOperation();
    try {
      final result = await operation();
      if (_disposed) {
        return;
      }
      result.fold(
        (_) {
          _error = null;
        },
        (failure) {
          final message = failure.toDisplayMessage();
          _error = message;
          AppLogger.error(
            '$logPrefix: $message',
            failure.toTechnicalMessage(),
          );
        },
      );
    } finally {
      _endOperation();
    }
  }
}
