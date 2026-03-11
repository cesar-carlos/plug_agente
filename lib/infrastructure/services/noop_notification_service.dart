import 'dart:developer' as developer;

import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:result_dart/result_dart.dart';

/// Implementação noop de INotificationService para ambientes sem suporte a notificações.
class NoopNotificationService implements INotificationService {
  @override
  Future<Result<void>> initialize() async {
    developer.log(
      'Notification service not available in degraded mode',
      name: 'noop_notification_service',
      level: 800,
    );
    return const Success(unit);
  }

  @override
  Future<Result<void>> show({
    required String title,
    required String body,
    String? payload,
  }) async {
    developer.log(
      'Notification request ignored (degraded mode): $title',
      name: 'noop_notification_service',
      level: 800,
    );
    return const Success(unit);
  }

  @override
  Future<Result<void>> schedule({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    developer.log(
      'Scheduled notification request ignored (degraded mode): $title',
      name: 'noop_notification_service',
      level: 800,
    );
    return const Success(unit);
  }

  @override
  Future<Result<void>> cancel(int id) async {
    return const Success(unit);
  }

  @override
  Future<Result<void>> cancelAll() async {
    return const Success(unit);
  }
}
