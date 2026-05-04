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
