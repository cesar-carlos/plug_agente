import 'package:plug_agente/application/validation/query_validation_messages.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:result_dart/result_dart.dart';

/// Use case para executar queries em streaming.
///
/// Valida a query e delega para o gateway de streaming.
class ExecuteStreamingQuery {
  ExecuteStreamingQuery(this._gateway, this._settings);
  final IStreamingDatabaseGateway _gateway;
  final IOdbcConnectionSettings _settings;

  /// Executa query em streaming.
  ///
  /// [query] é a SQL query a ser executada.
  /// [connectionString] é a string de conexão ODBC.
  /// [onChunk] é chamado para cada lote de linhas processado.
  /// [fetchSize] é o número de linhas buscadas por vez (default 1000).
  Future<Result<void>> call(
    String query,
    String connectionString,
    Future<void> Function(List<Map<String, dynamic>>) onChunk, {
    int fetchSize = 1000,
  }) async {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return Failure(
        domain.ValidationFailure(QueryValidationMessages.queryCannotBeEmpty),
      );
    }

    if (connectionString.trim().isEmpty) {
      return Failure(
        domain.ValidationFailure(
          QueryValidationMessages.connectionStringCannotBeEmpty,
        ),
      );
    }

    final validation = SqlValidator.validateSelectQuery(trimmedQuery);
    if (validation.isError()) {
      return Failure(validation.exceptionOrNull()!);
    }

    // Executar via gateway de streaming
    return _gateway.executeQueryStream(
      trimmedQuery,
      connectionString,
      onChunk,
      fetchSize: fetchSize,
      chunkSizeBytes: _settings.streamingChunkSizeKb * 1024,
    );
  }

  Future<Result<void>> cancelActiveStream({
    StreamingCancelReason reason = StreamingCancelReason.user,
  }) {
    return _gateway.cancelActiveStream(reason: reason);
  }
}
