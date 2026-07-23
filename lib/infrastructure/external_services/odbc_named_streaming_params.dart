import 'dart:typed_data';

// Deep import: serializeParams / paramValuesFromObjects are not on the public
// barrels; required to pass named params into native streamQueryBatched knobs.
import 'package:odbc_fast/infrastructure/native/protocol/param_value.dart'
    show paramValuesFromObjects, serializeParams;
import 'package:odbc_fast/odbc_fast.dart' show NamedParameterParser, ParameterMissingException;

/// Result of converting named `@param` / `:param` SQL into a cleaned statement
/// plus a native `paramsBuffer` for batched streaming.
final class OdbcNamedStreamingParams {
  const OdbcNamedStreamingParams({
    required this.cleanedSql,
    required this.paramsBuffer,
  });

  final String cleanedSql;
  final Uint8List paramsBuffer;
}

/// Builds a [OdbcNamedStreamingParams] for native `streamQueryBatched`.
///
/// Throws [ParameterMissingException] / [ArgumentError] when binding fails —
/// callers should fall back to `streamQueryNamed` or map to a typed failure.
OdbcNamedStreamingParams prepareNamedStreamingParams({
  required String sql,
  required Map<String, Object?> namedParameters,
}) {
  final extract = NamedParameterParser.extract(sql);
  final positional = NamedParameterParser.toPositionalParams(
    namedParams: namedParameters,
    paramNames: extract.paramNames,
  );
  return OdbcNamedStreamingParams(
    cleanedSql: extract.cleanedSql,
    paramsBuffer: serializeParams(paramValuesFromObjects(positional)),
  );
}
