import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/use_cases/cancel_all_notifications.dart';
import 'package:plug_agente/application/use_cases/cancel_notification.dart';
import 'package:plug_agente/application/use_cases/schedule_notification.dart';
import 'package:plug_agente/application/use_cases/send_notification.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/errors.dart';

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

  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _sendNotification(
      title: title,
      body: body,
      payload: payload,
    );

    result.fold(
      (success) {
        _isLoading = false;
      },
      (failure) {
        _error = failure.toDisplayMessage();
        AppLogger.error('Failed to send notification: $_error');
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  Future<void> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _scheduleNotification(
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      payload: payload,
    );

    result.fold(
      (success) {
        _isLoading = false;
      },
      (failure) {
        _error = failure.toDisplayMessage();
        AppLogger.error('Failed to send notification: $_error');
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  Future<void> cancelNotification(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _cancelNotification(id);

    result.fold(
      (success) {
        _isLoading = false;
      },
      (failure) {
        _error = failure.toDisplayMessage();
        AppLogger.error('Failed to send notification: $_error');
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  Future<void> cancelAllNotifications() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _cancelAllNotifications();

    result.fold(
      (success) {
        _isLoading = false;
      },
      (failure) {
        _error = failure.toDisplayMessage();
        AppLogger.error('Failed to send notification: $_error');
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
