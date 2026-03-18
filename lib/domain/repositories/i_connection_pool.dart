import 'package:result_dart/result_dart.dart';

/// Interface para pool de conexões ODBC.
abstract class IConnectionPool {
  /// Adquire uma conexão do pool ou cria uma nova se necessário.
  Future<Result<String>> acquire(String connectionString);

  /// Libera uma conexão de volta para o pool (não desconecta).
  Future<Result<void>> release(String connectionId);

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
