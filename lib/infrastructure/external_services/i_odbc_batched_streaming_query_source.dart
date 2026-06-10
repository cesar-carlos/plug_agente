import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_native_options.dart';
import 'package:result_dart/result_dart.dart';

/// Streams ODBC query chunks with explicit native `fetchSize` / `chunkSize`.
abstract class IOdbcBatchedStreamingQuerySource {
  Stream<Result<QueryResult>> streamQuery(
    int nativeConnectionId,
    String sql,
    OdbcStreamingNativeOptions options,
  );
}
