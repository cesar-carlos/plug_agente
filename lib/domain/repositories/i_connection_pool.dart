import 'package:odbc_fast/odbc_fast.dart';
import 'package:result_dart/result_dart.dart';

/// Interface para pool de conexoes ODBC.
abstract class IConnectionPool {
  /// Adquire uma conexao do pool ou cria uma nova se necessario.
  Future<Result<String>> acquire(
    String connectionString, {
    ConnectionOptions? options,
  });

  /// Libera uma conexao.
  ///
  /// A implementacao nativa devolve o handle ao pool; a implementacao por lease
  /// encerra a conexao fisica antes de liberar a vaga local.
  Future<Result<void>> release(String connectionId);

  /// Descarta uma conexao que nao deve voltar ao pool.
  ///
  /// Use quando timeout, cancelamento ou erro de handle deixa a conexao em
  /// estado incerto. Implementacoes devem liberar qualquer vaga local associada.
  Future<Result<void>> discard(String connectionId);

  /// Fecha todas as conexoes do pool.
  Future<Result<void>> closeAll();

  /// Recicla o pool associado a connection string.
  ///
  /// Fecha o pool atual (se existir) e forca recriacao no proximo acquire.
  Future<Result<void>> recycle(String connectionString);

  /// Retorna o numero de conexoes ativas no pool.
  Future<Result<int>> getActiveCount({String? connectionString});

  /// Executa health check em todos os pools.
  Future<Result<void>> healthCheckAll();
}

/// Optional capability for pools that can bound acquire wait time per request.
abstract class ITimedConnectionPoolAcquire {
  Future<Result<String>> acquireWithin(
    String connectionString, {
    ConnectionOptions? options,
    Duration? acquireTimeout,
  });
}

/// Optional capability for adaptive pools that can try an optionless native
/// acquire for simple SQL while preserving full [ConnectionOptions] on fallback.
abstract class INativeCompatibleConnectionPoolAcquire {
  Future<Result<String>> acquireNativeCompatible(
    String connectionString, {
    required ConnectionOptions leaseFallbackOptions,
    Duration? acquireTimeout,
  });
}

/// Optional capability for pools that can proactively warm connections.
abstract class IConnectionPoolWarmUp {
  Future<Result<void>> warmUp(
    String connectionString, {
    int? warmUpCount,
  });
}

/// Optional feedback surface for adaptive pools that need execution-stage
/// failures to influence their strategy selection.
abstract class IAdaptivePoolFeedback {
  void recordExecutionFailure({
    required String connectionString,
    required Object error,
    String? connectionId,
    String? stage,
  });
}

/// Optional diagnostics surface for health reporting.
abstract class IConnectionPoolDiagnostics {
  Map<String, Object?> getHealthDiagnostics();
}
