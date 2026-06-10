import 'dart:async';
import 'dart:math';

import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:result_dart/result_dart.dart';

/// Gerenciador de retries com exponential backoff.
///
/// Applies a multiplicative jitter on each retry delay (default ±20%) to avoid
/// synchronized retry storms when many in-flight operations fail at the same
/// time (e.g., after a circuit breaker closes or a network blip). A
/// deterministic [Random] can be injected from tests via the constructor.
class RetryManager implements IRetryManager {
  RetryManager({
    double jitterFactor = _defaultJitterFactor,
    Random? random,
  }) : assert(
         jitterFactor >= 0 && jitterFactor <= 1,
         'jitterFactor must be in [0, 1]',
       ),
       _jitterFactor = jitterFactor,
       _random = random ?? Random();

  static const int _defaultMaxAttempts = 3;
  static const int _defaultInitialDelayMs = 500;
  static const double _defaultBackoffMultiplier = 2;
  static const double _defaultJitterFactor = 0.2;

  final double _jitterFactor;
  final Random _random;

  @override
  Future<Result<T>> execute<T extends Object>(
    Future<Result<T>> Function() operation, {
    int maxAttempts = _defaultMaxAttempts,
    int initialDelayMs = _defaultInitialDelayMs,
    double backoffMultiplier = _defaultBackoffMultiplier,
  }) async {
    if (maxAttempts < 1) {
      return Failure(
        domain.ValidationFailure('maxAttempts must be at least 1, got $maxAttempts'),
      );
    }

    var attempts = 0;
    var delayMs = initialDelayMs;
    Exception? lastException;

    while (attempts < maxAttempts) {
      attempts++;

      Result<T> result;
      try {
        result = await operation();
      } on Exception catch (e) {
        lastException = e;

        // Se não deve retry ou última tentativa, propagar erro
        if (!isTransientFailure(lastException!) || attempts >= maxAttempts) {
          return Failure(_typedFailure(lastException!));
        }

        final jitteredDelay = _applyJitter(delayMs);
        AppLogger.info(
          'resilience: connect_attempt attempt=$attempts max=$maxAttempts '
          'delay_ms=$jitteredDelay base_ms=$delayMs',
        );
        await Future<void>.delayed(Duration(milliseconds: jitteredDelay));
        delayMs = (delayMs * backoffMultiplier).toInt();
        continue;
      }

      // Se sucesso, retornar imediatamente
      if (result.isSuccess()) {
        return result;
      }

      // Falha - armazenar e verificar se deve fazer retry
      result.fold((success) => throw StateError('Fold called on success'), (
        exception,
      ) {
        lastException = exception;
      });

      // Se não deve retry ou última tentativa, propagar erro
      if (!isTransientFailure(lastException!) || attempts >= maxAttempts) {
        return Failure(_typedFailure(lastException!));
      }

      final jitteredDelay = _applyJitter(delayMs);
      AppLogger.info(
        'resilience: connect_attempt attempt=$attempts max=$maxAttempts '
        'delay_ms=$jitteredDelay base_ms=$delayMs',
      );
      await Future<void>.delayed(Duration(milliseconds: jitteredDelay));
      delayMs = (delayMs * backoffMultiplier).toInt();
    }

    // All attempts failed — normalize to a typed domain Failure so callers
    // receive a consistent Result<T> type regardless of whether the operation
    // threw an Exception or returned a Failure Result.
    return Failure(_typedFailure(lastException!));
  }

  @override
  bool isTransientFailure(Exception exception) {
    if (exception is domain.Failure) {
      // Query execution may have reached the database already. Retrying
      // can duplicate non-idempotent DML — never retry regardless of isTransient.
      if (exception is domain.QueryExecutionFailure) {
        return false;
      }

      // Explicit context flags from the mapper take precedence over type-level
      // defaults for all failure subtypes.
      if (exception.context['retryable'] == true) return true;
      if (exception.context['retryable'] == false) return false;
      if (exception.context['poolExhausted'] == true) return true;

      // ConnectionFailure: context 'retryable' already checked above. Fall back
      // to the type-level isTransient (true by definition) when not overridden.
      // Auth/driver-not-found failures carry 'retryable': false from the mapper.
      if (exception is domain.ConnectionFailure) {
        return exception.isTransient; // true unless mapper set retryable:false
      }

      // NetworkFailure.isTransient is always true by domain definition; honour
      // explicit auth-failure messages as a content-level override.
      if (exception is domain.NetworkFailure) {
        final message = exception.message.toLowerCase();
        if (message.contains('authentication') || message.contains('invalid token') || message.contains('401')) {
          return false;
        }
        return exception.isTransient; // always true
      }

      // Delegate to the domain model for all other subtypes. Validation,
      // Configuration, Database, Server, Not-found, Compression, Notification.
      return exception.isTransient;
    }

    // For generic exceptions fall back to message heuristics.
    final message = exception.toString().toLowerCase();
    return message.contains('timeout') ||
        message.contains('connection') ||
        message.contains('network') ||
        message.contains('temporarily');
  }

  domain.Failure _typedFailure(Exception exception) {
    if (exception is domain.Failure) {
      return exception;
    }
    return domain.ServerFailure.withContext(
      message: 'Operation failed after retries',
      cause: exception,
      context: {'operation': 'retry_manager.execute'},
    );
  }

  /// Returns `baseDelayMs` perturbed by ±`_jitterFactor` (default ±20%).
  ///
  /// Avoids synchronized retry storms across concurrent operations. The result
  /// is clamped to at least `1ms` so the caller always yields the event loop.
  int _applyJitter(int baseDelayMs) {
    if (_jitterFactor == 0 || baseDelayMs <= 0) {
      return baseDelayMs;
    }
    final span = baseDelayMs * _jitterFactor;
    final offset = (_random.nextDouble() * 2 - 1) * span;
    final jittered = baseDelayMs + offset;
    return jittered < 1 ? 1 : jittered.round();
  }
}
