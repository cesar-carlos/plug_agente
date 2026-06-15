import 'package:odbc_fast/odbc_fast.dart';
import 'package:odbc_fast/odbc_fast_native.dart';
import 'package:plug_agente/infrastructure/external_services/i_odbc_batched_streaming_query_source.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_native_options.dart';
import 'package:result_dart/result_dart.dart';

/// Drives native columnar batched streaming with caller-provided fetch/chunk options.
///
/// Uses `streamQueryColumnarBatched` from `odbc_fast` 4.x so chunks stay columnar
/// until the gateway maps them into Hub row-map wire chunks.
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
  Stream<Result<QueryResult>> streamRowMajorQuery(
    int nativeConnectionId,
    String sql,
    OdbcStreamingNativeOptions options, {
    bool lazyStrings = false,
  }) async* {
    try {
      await for (final buffer in _streamRowMajorBatched(
        nativeConnectionId,
        sql,
        options,
        lazyStrings: lazyStrings,
      )) {
        yield Success(
          QueryResult(
            columns: buffer.columnNames,
            rows: buffer.rows,
            rowCount: buffer.rowCount,
          ),
        );
      }
    } on Exception catch (error) {
      yield Failure(error);
    }
  }

  @override
  Stream<Result<TypedColumnarResult>> streamColumnarQuery(
    int nativeConnectionId,
    String sql,
    OdbcStreamingNativeOptions options,
  ) async* {
    try {
      await for (final chunk in _streamColumnarBatched(
        nativeConnectionId,
        sql,
        options,
      )) {
        yield Success(chunk);
      }
    } on Exception catch (error) {
      yield Failure(error);
    }
  }

  Stream<ParsedRowBuffer> _streamRowMajorBatched(
    int nativeConnectionId,
    String sql,
    OdbcStreamingNativeOptions options, {
    required bool lazyStrings,
  }) {
    if (_isAsync) {
      return _asyncNative.streamQueryBatched(
        nativeConnectionId,
        sql,
        fetchSize: options.fetchSize,
        chunkSize: options.nativeChunkSizeBytes,
        maxBufferBytes: options.maxResultBufferBytes,
        resultEncodingWire: ResultEncoding.rowMajor.wireCode,
        lazyStrings: lazyStrings,
      );
    }

    return _syncNative.streamQueryBatched(
      nativeConnectionId,
      sql,
      fetchSize: options.fetchSize,
      chunkSize: options.nativeChunkSizeBytes,
      lazyStrings: lazyStrings,
    );
  }

  Stream<TypedColumnarResult> _streamColumnarBatched(
    int nativeConnectionId,
    String sql,
    OdbcStreamingNativeOptions options,
  ) {
    if (_isAsync) {
      return _asyncNative.streamQueryColumnarBatched(
        nativeConnectionId,
        sql,
        fetchSize: options.fetchSize,
        chunkSize: options.nativeChunkSizeBytes,
        maxBufferBytes: options.maxResultBufferBytes,
      );
    }

    return _syncNative.streamQueryColumnarBatched(
      nativeConnectionId,
      sql,
      fetchSize: options.fetchSize,
      chunkSize: options.nativeChunkSizeBytes,
    );
  }
}
