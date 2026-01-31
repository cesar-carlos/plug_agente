import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:result_dart/result_dart.dart';

/// Use case para executar queries em streaming.
///
/// Valida a query e delega para o gateway de streaming.
class ExecuteStreamingQuery {
  ExecuteStreamingQuery(this._gateway);
  final IStreamingDatabaseGateway _gateway;

  /// Executa query em streaming.
  ///
  /// [query] é a SQL query a ser executada.
  /// [connectionString] é a string de conexão ODBC.
  /// [onChunk] é chamado para cada lote de linhas processado.
  /// [fetchSize] é o número de linhas buscadas por vez (default 1000).
  Future<Result<void>> call(
    String query,
    String connectionString,
    void Function(List<Map<String, dynamic>>) onChunk, {
    int fetchSize = 1000,
  }) async {
    // Validação
    if (query.trim().isEmpty) {
      return Failure(domain.ValidationFailure('Query cannot be empty'));
    }

    if (connectionString.trim().isEmpty) {
      return Failure(
        domain.ValidationFailure('Connection string cannot be empty'),
      );
    }

    // Executar via gateway de streaming
    return _gateway.executeQueryStream(
      query,
      connectionString,
      onChunk,
      fetchSize: fetchSize,
      chunkSizeBytes: 1024 * 1024, // 1MB chunks
    );
  }
}
