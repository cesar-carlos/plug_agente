import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:result_dart/result_dart.dart';

class NotificationService implements INotificationService {
  NotificationService() : _plugin = FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;

  static const String _notificationGuid =
      'A181BB32-71A7-4B9E-9C3F-8E2D1B4A5C6D';

  @override
  Future<Result<void>> initialize() async {
    try {
      const initializationSettings = InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: AppConstants.appName,
          appUserModelId:
              'PlugDatabase.PlugAgente.App.${AppConstants.appVersion}',
          guid: _notificationGuid,
        ),
      );

      final result = await _plugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      if (result != null && !result) {
        return Failure(
          domain.NotificationFailure('Failed to initialize notifications'),
        );
      }

      return const Success<Object, Exception>(Object());
    } on Exception catch (e) {
      return Failure(
        domain.NotificationFailure('Failed to initialize notifications: $e'),
      );
    }
  }

  @override
  Future<Result<void>> show({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      const platformChannelSpecifics = NotificationDetails();

      await _plugin.show(
        0,
        title,
        body,
        platformChannelSpecifics,
        payload: payload,
      );

      return const Success<Object, Exception>(Object());
    } on Exception catch (e) {
      return Failure(
        domain.NotificationFailure('Failed to show notification: $e'),
      );
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
      const platformChannelSpecifics = NotificationDetails();

      // For Windows, schedule is not directly supported, so we use show() instead
      // This is a limitation of flutter_local_notifications on Windows desktop
      await _plugin.show(
        0,
        title,
        body,
        platformChannelSpecifics,
        payload: payload,
      );

      return const Success<Object, Exception>(Object());
    } on Exception catch (e) {
      return Failure(
        domain.NotificationFailure('Failed to schedule notification: $e'),
      );
    }
  }

  @override
  Future<Result<void>> cancel(int id) async {
    try {
      await _plugin.cancel(id);
      return const Success<Object, Exception>(Object());
    } on Exception catch (e) {
      return Failure(
        domain.NotificationFailure('Failed to cancel notification: $e'),
      );
    }
  }

  @override
  Future<Result<void>> cancelAll() async {
    try {
      await _plugin.cancelAll();
      return const Success<Object, Exception>(Object());
    } on Exception catch (e) {
      return Failure(
        domain.NotificationFailure('Failed to cancel all notifications: $e'),
      );
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    // Lógica para lidar com clique na notificação
  }
}
