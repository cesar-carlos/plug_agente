import 'dart:async';

import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:result_dart/result_dart.dart';

/// Gerenciador de retries com exponential backoff.
class RetryManager implements IRetryManager {
  RetryManager();

  static const int _defaultMaxAttempts = 3;
  static const int _defaultInitialDelayMs = 500;
  static const double _defaultBackoffMultiplier = 2;

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
          return Failure(lastException!);
        }

        AppLogger.info(
          'resilience: connect_attempt attempt=$attempts max=$maxAttempts delay_ms=$delayMs',
        );
        // Aguardar com exponential backoff para próxima tentativa
        await Future<void>.delayed(Duration(milliseconds: delayMs));
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
        return Failure(lastException!);
      }

      AppLogger.info(
        'resilience: connect_attempt attempt=$attempts max=$maxAttempts delay_ms=$delayMs',
      );
      // Aguardar com exponential backoff para próxima tentativa
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      delayMs = (delayMs * backoffMultiplier).toInt();
    }

    // All attempts failed — normalize to a typed domain Failure so callers
    // receive a consistent Result<T> type regardless of whether the operation
    // threw an Exception or returned a Failure Result.
    final last = lastException!;
    if (last is domain.Failure) {
      return Failure(last);
    }
    return Failure(
      domain.ServerFailure.withContext(
        message: last.toString(),
        cause: last,
        context: {'operation': 'retry_manager.execute'},
      ),
    );
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
        if (message.contains('authentication') ||
            message.contains('invalid token') ||
            message.contains('401')) {
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
}
