import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/i_odbc_batched_streaming_query_source.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_native_options.dart';
import 'package:result_dart/result_dart.dart';

/// Drives `streamQueryBatched` with caller-provided fetch/chunk options.
///
/// Mirrors the batched-first fallback used inside `odbc_fast` repository
/// streaming, but propagates [OdbcStreamingNativeOptions] to the native path.
class OdbcBatchedStreamingQuerySource implements IOdbcBatchedStreamingQuerySource {
  OdbcBatchedStreamingQuerySource({
    required AsyncNativeOdbcConnection asyncNative,
    required NativeOdbcConnection syncNative,
    required bool isAsync,
  }) : _asyncNative = asyncNative,
       _syncNative = syncNative,
       _isAsync = isAsync;

  final AsyncNativeOdbcConnection _asyncNative;
  final NativeOdbcConnection _syncNative;
  final bool _isAsync;

  @override
  Stream<Result<QueryResult>> streamQuery(
    int nativeConnectionId,
    String sql,
    OdbcStreamingNativeOptions options,
  ) async* {
    try {
      await for (final chunk in _streamNativeQueryWithFallback(
        nativeConnectionId,
        sql,
        options,
      )) {
        yield Success(_toQueryResult(chunk));
      }
    } on Exception catch (error) {
      yield Failure(error);
    }
  }

  Stream<ParsedRowBuffer> _streamNativeQueryWithFallback(
    int nativeConnectionId,
    String sql,
    OdbcStreamingNativeOptions options,
  ) async* {
    var emittedFromBatched = false;

    try {
      final batched = _isAsync
          ? _asyncNative.streamQueryBatched(
              nativeConnectionId,
              sql,
              fetchSize: options.fetchSize,
              chunkSize: options.nativeChunkSizeBytes,
              maxBufferBytes: options.maxResultBufferBytes,
            )
          : _syncNative.streamQueryBatched(
              nativeConnectionId,
              sql,
              fetchSize: options.fetchSize,
              chunkSize: options.nativeChunkSizeBytes,
            );

      await for (final chunk in batched) {
        emittedFromBatched = true;
        yield chunk;
      }
      return;
    } on Exception {
      if (emittedFromBatched) {
        rethrow;
      }
    }

    final fallback = _isAsync
        ? _asyncNative.streamQuery(
            nativeConnectionId,
            sql,
            maxBufferBytes: options.maxResultBufferBytes,
          )
        : _syncNative.streamQuery(nativeConnectionId, sql);

    await for (final chunk in fallback) {
      yield chunk;
    }
  }

  QueryResult _toQueryResult(ParsedRowBuffer buffer) {
    return QueryResult(
      columns: buffer.columnNames,
      rows: buffer.rows,
      rowCount: buffer.rowCount,
    );
  }
}
