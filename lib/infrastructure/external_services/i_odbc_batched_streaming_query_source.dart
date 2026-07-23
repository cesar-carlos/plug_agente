import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_native_options.dart';
import 'package:result_dart/result_dart.dart';

/// Streams ODBC query chunks with explicit native `fetchSize` / `chunkSize`.
abstract class IOdbcBatchedStreamingQuerySource {
  Stream<Result<TypedColumnarResult>> streamColumnarQuery(
    int nativeConnectionId,
    String sql,
    OdbcStreamingNativeOptions options, {
    Map<String, Object?>? namedParameters,
  });

  /// Row-major batched streaming with an explicit wire encoding override.
  ///
  /// SQL Anywhere must use this path so global service columnar defaults do not
  /// leak into `OdbcService.streamQuery`.
  Stream<Result<QueryResult>> streamRowMajorQuery(
    int nativeConnectionId,
    String sql,
    OdbcStreamingNativeOptions options, {
    bool lazyStrings = false,
    Map<String, Object?>? namedParameters,
  });
}
