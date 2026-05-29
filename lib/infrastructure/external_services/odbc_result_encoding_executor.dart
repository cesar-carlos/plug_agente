import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/config/odbc_result_encoding_config.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:result_dart/result_dart.dart';

/// Executes a single (non multi-result) ODBC query, choosing between the
/// default row-major call and the configured columnar/encoded path.
///
/// Extracted from `OdbcDatabaseGateway` so the result-encoding selection (env
/// driven) and the named→positional parameter handling live behind a focused,
/// testable surface. Holds only a log-throttle flag.
final class OdbcResultEncodingExecutor {
  OdbcResultEncodingExecutor(this._service);

  final OdbcService _service;
  ResultEncoding _lastLoggedResultEncoding = ResultEncoding.rowMajor;

  /// Runs [preparedExecution] honoring the configured result encoding.
  Future<Result<QueryResult>> execute(
    String connectionId,
    OdbcPreparedQueryExecution preparedExecution,
  ) {
    final resultEncoding = resolveOdbcResultEncoding();
    if (resultEncoding != ResultEncoding.rowMajor) {
      _logResultEncodingIfNeeded(resultEncoding);
    }

    return resultEncoding == ResultEncoding.rowMajor
        ? _executeRowMajor(connectionId, preparedExecution)
        : _executeWithEncoding(connectionId, preparedExecution, resultEncoding);
  }

  Future<Result<QueryResult>> _executeRowMajor(
    String connectionId,
    OdbcPreparedQueryExecution preparedExecution,
  ) {
    final parameters = preparedExecution.parameters;
    if (parameters != null && parameters.isNotEmpty) {
      return _service.executeQueryNamed(
        connectionId,
        preparedExecution.sql,
        parameters,
      );
    }

    return _service.executeQuery(
      preparedExecution.sql,
      connectionId: connectionId,
    );
  }

  Future<Result<QueryResult>> _executeWithEncoding(
    String connectionId,
    OdbcPreparedQueryExecution preparedExecution,
    ResultEncoding resultEncoding,
  ) {
    final parameters = preparedExecution.parameters;
    if (parameters == null || parameters.isEmpty) {
      return _service.executeQueryParams(
        connectionId,
        preparedExecution.sql,
        const <Object?>[],
        resultEncoding: resultEncoding,
      );
    }

    final parsed = NamedParameterParser.extract(preparedExecution.sql);
    final positionalParams = NamedParameterParser.toPositionalParams(
      namedParams: Map<String, Object?>.from(parameters),
      paramNames: parsed.paramNames,
    );
    return _service.executeQueryParams(
      connectionId,
      parsed.cleanedSql,
      positionalParams,
      resultEncoding: resultEncoding,
    );
  }

  void _logResultEncodingIfNeeded(ResultEncoding resultEncoding) {
    if (_lastLoggedResultEncoding == resultEncoding) {
      return;
    }
    _lastLoggedResultEncoding = resultEncoding;
    developer.log(
      'ODBC result encoding override enabled',
      name: 'database_gateway',
      level: 800,
      error: <String, Object?>{
        'env': odbcResultEncodingEnvKey,
        'result_encoding': resultEncodingConfigName(resultEncoding),
      },
    );
  }
}
