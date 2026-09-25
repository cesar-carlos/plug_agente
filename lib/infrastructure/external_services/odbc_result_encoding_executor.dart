import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:result_dart/result_dart.dart';

/// Executes a single (non multi-result) ODBC query as row-major [QueryResult].
///
/// `odbc_fast` clamps QueryResult APIs to row-major. Fetching columnar and
/// converting with `fromTypedColumnar` rebuilds `List<List>` and drops the
/// native gain. Columnar stays on the streaming path when the hub chunk
/// itself is columnar.
final class OdbcResultEncodingExecutor {
  OdbcResultEncodingExecutor(IQueryService queries) : _queries = queries;

  final IQueryService _queries;

  /// Runs [preparedExecution] as a row-major [QueryResult].
  Future<Result<QueryResult>> execute(
    String connectionId,
    OdbcPreparedQueryExecution preparedExecution, {
    DatabaseType? databaseType,
  }) {
    return _executeRowMajor(connectionId, preparedExecution);
  }

  Future<Result<QueryResult>> _executeRowMajor(
    String connectionId,
    OdbcPreparedQueryExecution preparedExecution,
  ) {
    final parameters = preparedExecution.parameters;
    if (parameters != null && parameters.isNotEmpty) {
      return _queries.executeQueryNamed(
        connectionId,
        preparedExecution.sql,
        parameters,
      );
    }

    return _queries.executeQuery(
      preparedExecution.sql,
      connectionId: connectionId,
    );
  }
}
