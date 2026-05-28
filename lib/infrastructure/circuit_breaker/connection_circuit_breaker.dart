import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
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
    int openStateLogStride = _defaultOpenStateLogStride,
  }) : assert(
         openStateLogStride > 0,
         'openStateLogStride must be greater than zero',
       ),
       _failureThreshold = failureThreshold,
       _resetTimeout = resetTimeout,
       _openStateLogStride = openStateLogStride;

  /// Default stride for fast-fail logs while the circuit is open.
  ///
  /// Under sustained load the hub may retry many requests against an open
  /// circuit. Logging every rejection produces a log storm without adding
  /// signal. We log the first rejection (already covered by the transition to
  /// `open`) and every [_defaultOpenStateLogStride]-th subsequent rejection.
  static const int _defaultOpenStateLogStride = 10;

  final int _failureThreshold;
  final Duration _resetTimeout;
  final int _openStateLogStride;

  CircuitState _state = CircuitState.closed;
  int _consecutiveFailures = 0;
  DateTime? _openedAt;
  // Ensures only one concurrent probe executes in half-open state; all other
  // callers fast-fail to prevent a thundering herd when the circuit reopens.
  bool _halfOpenProbeInProgress = false;
  // Number of fast-fail rejections delivered during the current open episode.
  // Reset when the circuit transitions out of `open`.
  int _openStateRejectionCount = 0;

  /// Current circuit breaker state.
  CircuitState get state => _state;

  /// Number of consecutive failures recorded.
  int get consecutiveFailures => _consecutiveFailures;

  /// Number of fast-fail rejections delivered during the current `open`
  /// episode. Resets when the circuit transitions out of `open` (manually,
  /// after the reset timeout, or via [reset]).
  int get openStateRejectionCount => _openStateRejectionCount;

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
        _openStateRejectionCount++;
        if (_shouldLogOpenStateRejection(_openStateRejectionCount)) {
          developer.log(
            'Circuit breaker OPEN for $connectionString',
            name: 'circuit_breaker',
            level: 900,
            error: {
              'connection_string': _maskConnectionString(connectionString),
              'elapsed_seconds': elapsed.inSeconds,
              'reset_timeout_seconds': _resetTimeout.inSeconds,
              'consecutive_failures': _consecutiveFailures,
              'rejections_during_open': _openStateRejectionCount,
              'log_stride': _openStateLogStride,
            },
          );
        }

        return Failure(
          domain.ConnectionFailure.withContext(
            message: 'Circuit breaker open for database connection (${elapsed.inSeconds}s/${_resetTimeout.inSeconds}s)',
            context: {
              'reason': OdbcContextConstants.circuitBreakerOpenReason,
              'consecutive_failures': _consecutiveFailures,
              'time_since_open_seconds': elapsed.inSeconds,
              'reset_timeout_seconds': _resetTimeout.inSeconds,
            },
          ),
        );
      }

      // Try half-open — but only one probe at a time.
      _state = CircuitState.halfOpen;
      _openStateRejectionCount = 0;
      developer.log(
        'Circuit breaker entering HALF-OPEN state',
        name: 'circuit_breaker',
        level: 800,
        error: {
          'connection_string': _maskConnectionString(connectionString),
        },
      );
    }

    // In half-open: allow exactly one probe; concurrent callers fast-fail so
    // a thundering herd does not overwhelm a recovering database.
    if (_state == CircuitState.halfOpen) {
      if (_halfOpenProbeInProgress) {
        return Failure(
          domain.ConnectionFailure.withContext(
            message: 'Circuit breaker half-open probe already in progress',
            context: {
              'reason': OdbcContextConstants.circuitBreakerOpenReason,
              'consecutive_failures': _consecutiveFailures,
            },
          ),
        );
      }
      _halfOpenProbeInProgress = true;
    }

    // Execute operation
    final result = await operation();

    return result.fold(
      (success) {
        _halfOpenProbeInProgress = false;
        _onSuccess(connectionString);
        return Success(success);
      },
      (failure) {
        _halfOpenProbeInProgress = false;
        if (failure is domain.Failure && _shouldRecordFailure(failure)) {
          _onFailure(connectionString, failure);
        }
        return Failure(failure);
      },
    );
  }

  bool _shouldRecordFailure(domain.Failure failure) {
    if (failure is domain.ConnectionFailure) {
      return !_isLocalPressureFailure(failure);
    }

    if (failure is domain.QueryExecutionFailure) {
      return _isConnectionQueryFailure(failure);
    }

    return false;
  }

  bool _isConnectionQueryFailure(domain.QueryExecutionFailure failure) {
    final reason = failure.context['reason']?.toString();
    return failure.context['connectionFailed'] == true &&
        (reason == OdbcContextConstants.connectionLostDuringQueryReason ||
            reason == OdbcContextConstants.odbcWorkerCrashedReason);
  }

  bool _isLocalPressureFailure(domain.ConnectionFailure failure) {
    final reason = failure.context['reason']?.toString();
    return failure.context['poolExhausted'] == true ||
        reason == OdbcContextConstants.poolExhaustedReason ||
        reason == OdbcContextConstants.poolWaitTimeoutReason ||
        reason == OdbcContextConstants.odbcWorkerBusyConnectReason ||
        reason == OdbcContextConstants.directConnectionLimitTimeoutReason ||
        reason == SqlPipelineContextConstants.sqlQueueFullReason ||
        reason == SqlPipelineContextConstants.queueWaitTimeoutReason;
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
    _openStateRejectionCount = 0;

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

  bool _shouldLogOpenStateRejection(int rejectionCount) {
    // Always log the first rejection of an open episode. After that, log every
    // [_openStateLogStride]-th rejection so sustained back-pressure does not
    // produce a log storm while still surfacing periodic visibility.
    if (rejectionCount == 1) return true;
    return rejectionCount % _openStateLogStride == 0;
  }

  void _onFailure(String connectionString, domain.Failure failure) {
    _consecutiveFailures++;

    if (_consecutiveFailures >= _failureThreshold && _state != CircuitState.open) {
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
    _halfOpenProbeInProgress = false;
    _openStateRejectionCount = 0;

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
