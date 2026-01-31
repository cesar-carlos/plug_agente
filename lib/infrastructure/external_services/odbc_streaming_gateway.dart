import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:result_dart/result_dart.dart';

/// Gateway com suporte a streaming para grandes datasets.
///
/// Usa OdbcService padrão para simplificar. Streaming completo
/// pode ser implementado posteriormente com AsyncNativeOdbcConnection.
class OdbcStreamingGateway implements IStreamingDatabaseGateway {
  OdbcStreamingGateway(this._service);
  final OdbcService _service;

  /// Helper para converter erros ODBC em String.
  String _odbcErrorMessage(Object error) {
    if (error is OdbcError) {
      return error.message;
    }
    return error.toString();
  }

  @override
  Future<Result<void>> executeQueryStream(
    String query,
    String connectionString,
    void Function(List<Map<String, dynamic>> chunk) onChunk, {
    int fetchSize = 1000,
    int chunkSizeBytes = 1024 * 1024,
  }) async {
    // Conectar
    final connResult = await _service.connect(connectionString);

    return connResult.fold(
      (connection) async {
        // Executar query
        final result = await _service.executeQuery(connection.id, query);

        // Desconectar
        await _service.disconnect(connection.id);

        return result.fold(
          (queryResult) {
            // Converter e notificar via callback (implementação simplificada)
            final rows = _convertQueryResultToMaps(queryResult);
            if (rows.isNotEmpty) {
              onChunk(rows);
            }
            return const Success(unit);
          },
          (error) {
            return Failure(
              domain.QueryExecutionFailure(_odbcErrorMessage(error)),
            );
          },
        );
      },
      (error) {
        return Failure(domain.ConnectionFailure(_odbcErrorMessage(error)));
      },
    );
  }

  /// Converte QueryResult para lista de maps.
  List<Map<String, dynamic>> _convertQueryResultToMaps(QueryResult result) {
    return result.rows.map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < result.columns.length; i++) {
        map[result.columns[i]] = row[i];
      }
      return map;
    }).toList();
  }
}
