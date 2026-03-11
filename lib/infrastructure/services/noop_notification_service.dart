import 'dart:developer' as developer;

import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:result_dart/result_dart.dart';

/// Implementação noop de INotificationService para ambientes sem suporte a notificações.
class NoopNotificationService implements INotificationService {
  bool _didLogUnavailable = false;
  bool _didLogShowIgnored = false;
  bool _didLogScheduleIgnored = false;

  @override
  Future<Result<void>> initialize() async {
    if (!_didLogUnavailable) {
      developer.log(
        'Notification service not available in degraded mode',
        name: 'noop_notification_service',
        level: 800,
      );
      _didLogUnavailable = true;
    }
    return const Success(unit);
  }

  @override
  Future<Result<void>> show({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_didLogShowIgnored) {
      developer.log(
        'Notification requests are ignored in degraded mode',
        name: 'noop_notification_service',
        level: 800,
      );
      _didLogShowIgnored = true;
    }
    return const Success(unit);
  }

  @override
  Future<Result<void>> schedule({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    if (!_didLogScheduleIgnored) {
      developer.log(
        'Scheduled notification requests are ignored in degraded mode',
        name: 'noop_notification_service',
        level: 800,
      );
      _didLogScheduleIgnored = true;
    }
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
