import 'dart:async';

import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:result_dart/result_dart.dart';

/// Gerenciador de retries com exponential backoff.
class RetryManager implements IRetryManager {
  RetryManager._();

  static RetryManager? _instance;
  static RetryManager get instance => _instance ??= RetryManager._();

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

      // Aguardar com exponential backoff para próxima tentativa
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      delayMs = (delayMs * backoffMultiplier).toInt();
    }

    // Todas as tentativas falharam
    return Failure(lastException!);
  }

  @override
  bool isTransientFailure(Exception exception) {
    // Verificar se é um Failure do domínio com mensagem transitória
    if (exception is domain.Failure) {
      // Erros de conexão podem ser transientes
      if (exception is domain.ConnectionFailure) {
        final message = exception.message.toLowerCase();
        return message.contains('timeout') ||
            message.contains('connection') ||
            message.contains('network') ||
            message.contains('temporarily');
      }

      // Erros de query NÃO são transientes (SQL error, syntax error)
      if (exception is domain.QueryExecutionFailure) {
        return false;
      }

      // Erros de validação NÃO são transientes
      if (exception is domain.ValidationFailure) {
        return false;
      }

      // Configuration failure NÃO é transiente
      if (exception is domain.ConfigurationFailure) {
        return false;
      }

      // Outros erros: não fazer retry por segurança
      return false;
    }

    // Para exceções genéricas, verificar a mensagem
    final message = exception.toString().toLowerCase();
    return message.contains('timeout') ||
        message.contains('connection') ||
        message.contains('network') ||
        message.contains('temporarily');
  }
}
