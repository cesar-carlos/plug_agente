import 'package:result_dart/result_dart.dart';

/// Interface para gerenciar retries de operações que podem falhar.
abstract class IRetryManager {
  /// Executa uma operação com retry automático em caso de falha.
  ///
  /// [operation] é a função a ser executada.
  /// [maxAttempts] é o número máximo de tentativas (default 3).
  /// [initialDelayMs] é o delay inicial em milissegundos (default 500ms).
  /// [backoffMultiplier] é o multiplicador para exponential backoff (default 2.0).
  Future<Result<T>> execute<T extends Object>(
    Future<Result<T>> Function() operation, {
    int maxAttempts,
    int initialDelayMs,
    double backoffMultiplier,
  });

  /// Verifica se uma falha é transitória (passível de retry).
  bool isTransientFailure(Exception exception);
}
