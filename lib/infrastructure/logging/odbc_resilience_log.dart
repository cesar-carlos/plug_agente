import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/logger/log_rate_limiter.dart';
import 'package:plug_agente/core/security/odbc_connection_fingerprint.dart';

/// Structured, rate-limited records for ODBC recovery events.
abstract final class OdbcResilienceLog {
  static final LogRateLimiter _limiter = LogRateLimiter();

  static void warning({
    required String event,
    String? connectionString,
    String? reason,
    String? stage,
    int? attempt,
    int? maxAttempts,
    int? delayMs,
    int? elapsedMs,
    String? failureCode,
    String? sqlState,
    int? nativeCode,
    bool? retryable,
  }) {
    _record(
      event: event,
      level: _Level.warning,
      connectionString: connectionString,
      reason: reason,
      stage: stage,
      attempt: attempt,
      maxAttempts: maxAttempts,
      delayMs: delayMs,
      elapsedMs: elapsedMs,
      failureCode: failureCode,
      sqlState: sqlState,
      nativeCode: nativeCode,
      retryable: retryable,
    );
  }

  static void operational({
    required String event,
    String? connectionString,
    String? reason,
    String? stage,
    int? attempt,
    int? elapsedMs,
  }) {
    _record(
      event: event,
      level: _Level.operational,
      connectionString: connectionString,
      reason: reason,
      stage: stage,
      attempt: attempt,
      elapsedMs: elapsedMs,
    );
  }

  static void _record({
    required String event,
    required _Level level,
    String? connectionString,
    String? reason,
    String? stage,
    int? attempt,
    int? maxAttempts,
    int? delayMs,
    int? elapsedMs,
    String? failureCode,
    String? sqlState,
    int? nativeCode,
    bool? retryable,
  }) {
    final dsn = connectionString == null ? null : OdbcConnectionFingerprint.of(connectionString);
    final category = '$event:${dsn ?? '-'}';
    if (!_limiter.shouldLog(category)) {
      return;
    }
    final context = <String, dynamic>{
      'event': event,
      'dsn': ?dsn,
      'reason': ?reason,
      'stage': ?stage,
      'attempt': ?attempt,
      'max_attempts': ?maxAttempts,
      'delay_ms': ?delayMs,
      'elapsed_ms': ?elapsedMs,
      'failure_code': ?failureCode,
      'sqlstate': ?sqlState,
      'native_code': ?nativeCode,
      'retryable': ?retryable,
    };
    final message = 'odbc resilience: $event';
    switch (level) {
      case _Level.warning:
        AppLogger.warning(message, null, null, context);
      case _Level.operational:
        AppLogger.operational(message, context: context);
    }
  }
}

enum _Level { warning, operational }
