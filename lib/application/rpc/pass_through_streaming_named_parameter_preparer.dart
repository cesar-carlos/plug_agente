import 'package:plug_agente/domain/query/prepared_query_execution.dart';
import 'package:plug_agente/domain/streaming/i_streaming_named_parameter_preparer.dart';
import 'package:result_dart/result_dart.dart';

/// Application fallback that forwards SQL/parameters without ODBC-native parsing.
final class PassThroughStreamingNamedParameterPreparer implements IStreamingNamedParameterPreparer {
  const PassThroughStreamingNamedParameterPreparer();

  static const PassThroughStreamingNamedParameterPreparer instance = PassThroughStreamingNamedParameterPreparer();

  @override
  Result<OdbcPreparedQueryExecution> prepare({
    required String sql,
    Map<String, dynamic>? parameters,
  }) {
    return Success(
      OdbcPreparedQueryExecution(sql: sql, parameters: parameters),
    );
  }
}
