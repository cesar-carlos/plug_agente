import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Circuit breaker states following the classic pattern.
enum CircuitState {
  /// Circuit is closed, requests flow normally.
  closed,

  /// Circuit is open, requests fail fast without attempting operation.
  open,

  /// Circuit is testing if service has recovered.
  halfOpen,
}

/// Circuit breaker for database connections to prevent cascading failures.
///
/// When a connection fails repeatedly, the circuit breaker opens and fails
/// fast on subsequent requests without attempting the connection. After a
/// reset timeout, it enters half-open state to test recovery.
///
/// Usage:
/// ```dart
/// final breaker = ConnectionCircuitBreaker(
///   failureThreshold: 5,
///   resetTimeout: Duration(seconds: 30),
/// );
///
/// final result = await breaker.execute(
///   connectionString,
///   () => gateway.executeQuery(request),
/// );
/// ```
class ConnectionCircuitBreaker {
  ConnectionCircuitBreaker({
    required int failureThreshold,
    required Duration resetTimeout,
  })  : _failureThreshold = failureThreshold,
        _resetTimeout = resetTimeout;

  final int _failureThreshold;
  final Duration _resetTimeout;

  CircuitState _state = CircuitState.closed;
  int _consecutiveFailures = 0;
  DateTime? _openedAt;

  /// Current circuit breaker state.
  CircuitState get state => _state;

  /// Number of consecutive failures recorded.
  int get consecutiveFailures => _consecutiveFailures;

  /// Whether the circuit breaker is currently open.
  bool get isOpen => _state == CircuitState.open;

  /// Executes an operation through the circuit breaker.
  ///
  /// Returns [Result<T>] containing either:
  /// - Success(T): Operation completed successfully
  /// - Failure(ConnectionFailure): Circuit is open (fast fail)
  /// - Failure: Operation failed (from the operation itself)
  Future<Result<T>> execute<T extends Object>(
    String connectionString,
    Future<Result<T>> Function() operation,
  ) async {
    if (_state == CircuitState.open) {
      final elapsed = DateTime.now().difference(_openedAt!);
      if (elapsed < _resetTimeout) {
        developer.log(
          'Circuit breaker OPEN for $connectionString',
          name: 'circuit_breaker',
          level: 900,
          error: {
            'connection_string': _maskConnectionString(connectionString),
            'elapsed_seconds': elapsed.inSeconds,
            'reset_timeout_seconds': _resetTimeout.inSeconds,
            'consecutive_failures': _consecutiveFailures,
          },
        );

        return Failure(
          domain.ConnectionFailure.withContext(
            message:
                'Circuit breaker open for database connection (${elapsed.inSeconds}s/${_resetTimeout.inSeconds}s)',
            context: {
              'reason': 'circuit_breaker_open',
              'consecutive_failures': _consecutiveFailures,
              'time_since_open_seconds': elapsed.inSeconds,
              'reset_timeout_seconds': _resetTimeout.inSeconds,
            },
          ),
        );
      }

      // Try half-open
      _state = CircuitState.halfOpen;
      developer.log(
        'Circuit breaker entering HALF-OPEN state',
        name: 'circuit_breaker',
        level: 800,
        error: {
          'connection_string': _maskConnectionString(connectionString),
        },
      );
    }

    // Execute operation
    final result = await operation();

    return result.fold(
      (success) {
        _onSuccess(connectionString);
        return Success(success);
      },
      (failure) {
        if (failure is domain.ConnectionFailure) {
          _onFailure(connectionString, failure);
        }
        return Failure(failure);
      },
    );
  }

  void _onSuccess(String connectionString) {
    if (_consecutiveFailures > 0) {
      developer.log(
        'Circuit breaker recovered after $_consecutiveFailures failures',
        name: 'circuit_breaker',
        level: 800,
        error: {
          'connection_string': _maskConnectionString(connectionString),
          'previous_failures': _consecutiveFailures,
        },
      );
    }

    _consecutiveFailures = 0;

    if (_state == CircuitState.halfOpen) {
      _state = CircuitState.closed;
      developer.log(
        'Circuit breaker CLOSED',
        name: 'circuit_breaker',
        level: 800,
        error: {
          'connection_string': _maskConnectionString(connectionString),
        },
      );
    }
  }

  void _onFailure(String connectionString, domain.ConnectionFailure failure) {
    _consecutiveFailures++;

    if (_consecutiveFailures >= _failureThreshold &&
        _state != CircuitState.open) {
      _state = CircuitState.open;
      _openedAt = DateTime.now();

      developer.log(
        'Circuit breaker OPENED after $_consecutiveFailures failures',
        name: 'circuit_breaker',
        level: 1000,
        error: {
          'connection_string': _maskConnectionString(connectionString),
          'consecutive_failures': _consecutiveFailures,
          'threshold': _failureThreshold,
          'reset_timeout_seconds': _resetTimeout.inSeconds,
          'last_failure': failure.message,
        },
      );
    } else {
      developer.log(
        'Connection failure recorded ($_consecutiveFailures/$_failureThreshold)',
        name: 'circuit_breaker',
        level: 900,
        error: {
          'connection_string': _maskConnectionString(connectionString),
          'consecutive_failures': _consecutiveFailures,
          'threshold': _failureThreshold,
        },
      );
    }
  }

  /// Resets the circuit breaker to closed state.
  ///
  /// Useful for manual recovery or testing.
  void reset() {
    _state = CircuitState.closed;
    _consecutiveFailures = 0;
    _openedAt = null;

    developer.log(
      'Circuit breaker manually reset',
      name: 'circuit_breaker',
      level: 800,
    );
  }

  /// Masks sensitive parts of connection string for logging.
  String _maskConnectionString(String connectionString) {
    // Mask password if present
    return connectionString.replaceAllMapped(
      RegExp('PWD=([^;]+)', caseSensitive: false),
      (match) => 'PWD=***',
    );
  }
}
