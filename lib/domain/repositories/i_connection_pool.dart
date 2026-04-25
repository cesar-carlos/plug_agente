import 'package:result_dart/result_dart.dart';

/// Interface para pool de conexões ODBC.
abstract class IConnectionPool {
  /// Adquire uma conexão do pool ou cria uma nova se necessário.
  Future<Result<String>> acquire(String connectionString);

  /// Libera uma conexão.
  ///
  /// A implementação nativa devolve o handle ao pool; a implementação por lease
  /// encerra a conexão física antes de liberar a vaga local.
  Future<Result<void>> release(String connectionId);

  /// Descarta uma conexão que não deve voltar ao pool.
  ///
  /// Use quando timeout, cancelamento ou erro de handle deixa a conexão em
  /// estado incerto. Implementações devem liberar qualquer vaga local associada.
  Future<Result<void>> discard(String connectionId);

  /// Fecha todas as conexões do pool.
  Future<Result<void>> closeAll();

  /// Recicla o pool associado à connection string.
  ///
  /// Fecha o pool atual (se existir) e força recriação no próximo acquire.
  Future<Result<void>> recycle(String connectionString);

  /// Retorna o número de conexões ativas no pool.
  Future<Result<int>> getActiveCount();

  /// Executa health check em todos os pools.
  Future<Result<void>> healthCheckAll();
}
