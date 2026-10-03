import 'package:odbc_fast/odbc_fast.dart';
import 'package:odbc_fast/odbc_fast_native.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/i_odbc_batched_streaming_query_source.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_native_options.dart';
import 'package:result_dart/result_dart.dart';

/// Drives native columnar batched streaming with caller-provided fetch/chunk options.
///
/// Uses `streamQueryColumnarBatched` from `odbc_fast` 4.x so chunks stay columnar
/// until the gateway maps them into Hub row-map wire chunks. Named parameters use
/// the public named Result service and convert to [TypedColumnarResult] only
/// when a typed columnar consumer requires it.
class OdbcBatchedStreamingQuerySource implements IOdbcBatchedStreamingQuerySource {
  OdbcBatchedStreamingQuerySource({
    required AsyncNativeOdbcConnection asyncNative,
    required NativeOdbcConnection syncNative,
    required bool isAsync,
    required OdbcService service,
  }) : _asyncNative = asyncNative,
       _syncNative = syncNative,
       _isAsync = isAsync,
       _service = service;

  final AsyncNativeOdbcConnection _asyncNative;
  final NativeOdbcConnection _syncNative;
  final bool _isAsync;
  final OdbcService _service;

  @override
  Stream<Result<QueryResult>> streamRowMajorQuery(
    int nativeConnectionId,
    String sql,
    OdbcStreamingNativeOptions options, {
    bool lazyStrings = false,
    Map<String, Object?>? namedParameters,
  }) async* {
    try {
      if (namedParameters != null && namedParameters.isNotEmpty) {
        yield* _service.streamQueryNamed(
          nativeConnectionId.toString(),
          sql,
          namedParameters,
          fetchSize: options.fetchSize,
          chunkSize: options.nativeChunkSizeBytes,
        );
        return;
      }
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
    } on Object catch (error) {
      yield Failure(OdbcFailureMapper.mapStreamingError(error));
    }
  }

  @override
  Stream<Result<TypedColumnarResult>> streamColumnarQuery(
    int nativeConnectionId,
    String sql,
    OdbcStreamingNativeOptions options, {
    Map<String, Object?>? namedParameters,
  }) async* {
    try {
      if (namedParameters != null && namedParameters.isNotEmpty) {
        // Columnar batched native APIs do not accept paramsBuffer; reuse the
        // row-major batched+params path and rematerialize typed columns.
        await for (final rowMajor in streamRowMajorQuery(
          nativeConnectionId,
          sql,
          options,
          namedParameters: namedParameters,
        )) {
          yield rowMajor.map(toTypedColumnar);
        }
        return;
      }

      await for (final chunk in _streamColumnarBatched(
        nativeConnectionId,
        sql,
        options,
      )) {
        yield Success(chunk);
      }
    } on Object catch (error) {
      yield Failure(OdbcFailureMapper.mapStreamingError(error));
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
