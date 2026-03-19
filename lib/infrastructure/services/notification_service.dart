import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:result_dart/result_dart.dart';

class NotificationService implements INotificationService {
  NotificationService() : _plugin = FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;

  static const String _notificationGuid = AppConstants.notificationAppUserModelGuid;

  domain.NotificationFailure _buildFailure(
    String message, {
    Object? cause,
    Map<String, dynamic> context = const {},
  }) {
    return domain.NotificationFailure.withContext(
      message: message,
      cause: cause,
      context: context,
    );
  }

  @override
  Future<Result<void>> initialize() async {
    try {
      const initializationSettings = InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: AppConstants.appName,
          appUserModelId: 'PlugDatabase.PlugAgente.App.${AppConstants.appVersion}',
          guid: _notificationGuid,
        ),
      );

      final result = await _plugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      if (result != null && !result) {
        return Failure(
          _buildFailure(
            'Failed to initialize notifications',
            context: {'operation': 'initialize'},
          ),
        );
      }

      return const Success<Object, Exception>(Object());
    } on Exception catch (error) {
      return Failure(
        _buildFailure(
          'Failed to initialize notifications',
          cause: error,
          context: {'operation': 'initialize'},
        ),
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
        id: 0,
        title: title,
        body: body,
        notificationDetails: platformChannelSpecifics,
        payload: payload,
      );

      return const Success<Object, Exception>(Object());
    } on Exception catch (error) {
      return Failure(
        _buildFailure(
          'Failed to show notification',
          cause: error,
          context: {
            'operation': 'show',
            'title': title,
          },
        ),
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
        id: 0,
        title: title,
        body: body,
        notificationDetails: platformChannelSpecifics,
        payload: payload,
      );

      return const Success<Object, Exception>(Object());
    } on Exception catch (error) {
      return Failure(
        _buildFailure(
          'Failed to schedule notification',
          cause: error,
          context: {
            'operation': 'schedule',
            'title': title,
            'scheduledTime': scheduledTime.toIso8601String(),
          },
        ),
      );
    }
  }

  @override
  Future<Result<void>> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
      return const Success<Object, Exception>(Object());
    } on Exception catch (error) {
      return Failure(
        _buildFailure(
          'Failed to cancel notification',
          cause: error,
          context: {
            'operation': 'cancel',
            'notificationId': id,
          },
        ),
      );
    }
  }

  @override
  Future<Result<void>> cancelAll() async {
    try {
      await _plugin.cancelAll();
      return const Success<Object, Exception>(Object());
    } on Exception catch (error) {
      return Failure(
        _buildFailure(
          'Failed to cancel all notifications',
          cause: error,
          context: {'operation': 'cancelAll'},
        ),
      );
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    // Lógica para lidar com clique na notificação
  }
}
