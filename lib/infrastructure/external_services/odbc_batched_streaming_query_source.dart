import 'dart:typed_data';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:odbc_fast/odbc_fast_native.dart';
import 'package:plug_agente/infrastructure/external_services/i_odbc_batched_streaming_query_source.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_named_streaming_params.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_native_options.dart';
import 'package:result_dart/result_dart.dart';

/// Drives native columnar batched streaming with caller-provided fetch/chunk options.
///
/// Uses `streamQueryColumnarBatched` from `odbc_fast` 4.x so chunks stay columnar
/// until the gateway maps them into Hub row-map wire chunks. Named parameters use
/// row-major `streamQueryBatched` + `paramsBuffer` (columnar batched has no params
/// API) and convert to [TypedColumnarResult] when needed.
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
    Map<String, Object?>? namedParameters,
  }) async* {
    try {
      final prepared = _prepareSqlAndParams(sql, namedParameters);
      await for (final buffer in _streamRowMajorBatched(
        nativeConnectionId,
        prepared.sql,
        options,
        lazyStrings: lazyStrings,
        paramsBuffer: prepared.paramsBuffer,
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
    } on Exception catch (error) {
      yield Failure(error);
    }
  }

  ({String sql, Uint8List? paramsBuffer}) _prepareSqlAndParams(
    String sql,
    Map<String, Object?>? namedParameters,
  ) {
    if (namedParameters == null || namedParameters.isEmpty) {
      return (sql: sql, paramsBuffer: null);
    }
    final prepared = prepareNamedStreamingParams(
      sql: sql,
      namedParameters: namedParameters,
    );
    return (sql: prepared.cleanedSql, paramsBuffer: prepared.paramsBuffer);
  }

  Stream<ParsedRowBuffer> _streamRowMajorBatched(
    int nativeConnectionId,
    String sql,
    OdbcStreamingNativeOptions options, {
    required bool lazyStrings,
    Uint8List? paramsBuffer,
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
        paramsBuffer: paramsBuffer,
      );
    }

    return _syncNative.streamQueryBatched(
      nativeConnectionId,
      sql,
      fetchSize: options.fetchSize,
      chunkSize: options.nativeChunkSizeBytes,
      lazyStrings: lazyStrings,
      paramsBuffer: paramsBuffer,
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
