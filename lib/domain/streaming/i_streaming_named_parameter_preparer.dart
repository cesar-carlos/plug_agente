import 'package:plug_agente/domain/query/prepared_query_execution.dart';
import 'package:result_dart/result_dart.dart';

/// Prepares named parameters for ODBC streaming queries.
abstract interface class IStreamingNamedParameterPreparer {
  Result<OdbcPreparedQueryExecution> prepare({
    required String sql,
    Map<String, dynamic>? parameters,
  });
}
