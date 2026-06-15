import 'package:odbc_fast/odbc_fast.dart' show NamedParameterParser, ParameterMissingException;
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/query/prepared_query_execution.dart';
import 'package:plug_agente/domain/streaming/i_streaming_named_parameter_preparer.dart';
import 'package:result_dart/result_dart.dart';

/// Prepares named parameters for ODBC streaming using the ParamValues 4.x parser.
final class OdbcStreamingNamedParameterPreparer implements IStreamingNamedParameterPreparer {
  const OdbcStreamingNamedParameterPreparer();

  static const OdbcStreamingNamedParameterPreparer instance = OdbcStreamingNamedParameterPreparer();

  @override
  Result<OdbcPreparedQueryExecution> prepare({
    required String sql,
    Map<String, dynamic>? parameters,
  }) {
    if (parameters == null || parameters.isEmpty) {
      return Success(
        OdbcPreparedQueryExecution(sql: sql, parameters: null),
      );
    }

    try {
      final parsed = NamedParameterParser.extract(sql);
      NamedParameterParser.toPositionalParams(
        namedParams: Map<String, Object?>.from(parameters),
        paramNames: parsed.paramNames,
      );
      return Success(
        OdbcPreparedQueryExecution(
          sql: sql,
          parameters: parameters,
        ),
      );
    } on ParameterMissingException catch (error) {
      return Failure(
        domain.ValidationFailure(
          'Streaming query is missing bound parameter values: ${error.message}',
        ),
      );
    }
  }
}
