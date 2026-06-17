import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/use_cases/cancel_all_notifications.dart';
import 'package:plug_agente/application/use_cases/cancel_notification.dart';
import 'package:plug_agente/application/use_cases/schedule_notification.dart';
import 'package:plug_agente/application/use_cases/send_notification.dart';
import 'package:plug_agente/presentation/providers/presentation_error_state.dart';

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
  PresentationErrorState? _errorState;

  bool get isLoading => _isLoading;
  PresentationErrorState? get errorState => _errorState;
  String? get error => _errorState?.message;
  bool get errorCanRetry => _errorState?.canRetry ?? false;

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    _isLoading = true;
    _clearErrorState();
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
        _applyFailure(failure);
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
    _clearErrorState();
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
        _applyFailure(failure);
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  Future<void> cancelNotification(int id) async {
    _isLoading = true;
    _clearErrorState();
    notifyListeners();

    final result = await _cancelNotification(id);

    result.fold(
      (success) {
        _isLoading = false;
      },
      (failure) {
        _applyFailure(failure);
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  Future<void> cancelAllNotifications() async {
    _isLoading = true;
    _clearErrorState();
    notifyListeners();

    final result = await _cancelAllNotifications();

    result.fold(
      (success) {
        _isLoading = false;
      },
      (failure) {
        _applyFailure(failure);
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  void clearError() {
    if (_errorState == null) {
      return;
    }
    _clearErrorState();
    notifyListeners();
  }

  void _applyFailure(Object failure) {
    _errorState = PresentationErrorState.fromFailure(failure);
  }

  void _clearErrorState() {
    _errorState = null;
  }
}
