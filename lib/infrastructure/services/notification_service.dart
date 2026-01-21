import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:result_dart/result_dart.dart';

import '../../domain/repositories/i_notification_service.dart';
import '../../domain/errors/failures.dart' as domain;

class NotificationService implements INotificationService {
  final FlutterLocalNotificationsPlugin _plugin;

  NotificationService() : _plugin = FlutterLocalNotificationsPlugin();

  @override
  Future<Result<void>> initialize() async {
    try {
      const InitializationSettings initializationSettings = InitializationSettings();

      final result = await _plugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      if (result != null && !result) {
        return Failure(domain.NotificationFailure('Failed to initialize notifications'));
      }

      return Success<Object, Exception>(Object());
    } catch (e) {
      return Failure(domain.NotificationFailure('Failed to initialize notifications: $e'));
    }
  }

  @override
  Future<Result<void>> show({required String title, required String body, String? payload}) async {
    try {
      const NotificationDetails platformChannelSpecifics = NotificationDetails();

      await _plugin.show(0, title, body, platformChannelSpecifics, payload: payload);

      return Success<Object, Exception>(Object());
    } catch (e) {
      return Failure(domain.NotificationFailure('Failed to show notification: $e'));
    }
  }

  @override
  Future<Result<void>> schedule({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    try {
      const NotificationDetails platformChannelSpecifics = NotificationDetails();

      // For Windows, schedule is not directly supported, so we use show() instead
      // This is a limitation of flutter_local_notifications on Windows desktop
      await _plugin.show(0, title, body, platformChannelSpecifics, payload: payload);

      return Success<Object, Exception>(Object());
    } catch (e) {
      return Failure(domain.NotificationFailure('Failed to schedule notification: $e'));
    }
  }

  @override
  Future<Result<void>> cancel(int id) async {
    try {
      await _plugin.cancel(id);
      return Success<Object, Exception>(Object());
    } catch (e) {
      return Failure(domain.NotificationFailure('Failed to cancel notification: $e'));
    }
  }

  @override
  Future<Result<void>> cancelAll() async {
    try {
      await _plugin.cancelAll();
      return Success<Object, Exception>(Object());
    } catch (e) {
      return Failure(domain.NotificationFailure('Failed to cancel all notifications: $e'));
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    // Lógica para lidar com clique na notificação
  }
}
