import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/i_odbc_batched_streaming_query_source.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_native_options.dart';
import 'package:result_dart/result_dart.dart';

/// Opens columnar or row-major ODBC streaming query streams.
final class OdbcStreamingQueryStreamOpener {
  OdbcStreamingQueryStreamOpener({
    required OdbcService service,
    IOdbcBatchedStreamingQuerySource? batchedQuerySource,
  }) : _service = service,
       _batchedQuerySource = batchedQuerySource;

  final OdbcService _service;
  final IOdbcBatchedStreamingQuerySource? _batchedQuerySource;

  Stream<Result<TypedColumnarResult>> openColumnar({
    required String connectionId,
    required String query,
    required OdbcStreamingNativeOptions nativeStreamingOptions,
    Map<String, dynamic>? parameters,
  }) {
    if (parameters != null && parameters.isNotEmpty) {
      return _service.streamQueryNamed(connectionId, query, parameters).map((result) => result.map(toTypedColumnar));
    }

    final batchedSource = _batchedQuerySource;
    if (batchedSource == null) {
      return _service.streamQueryColumnar(connectionId, query);
    }

    final nativeConnectionId = int.tryParse(connectionId);
    if (nativeConnectionId == null || nativeConnectionId <= 0) {
      return _service.streamQueryColumnar(connectionId, query);
    }

    return batchedSource.streamColumnarQuery(
      nativeConnectionId,
      query,
      nativeStreamingOptions,
    );
  }

  Stream<Result<QueryResult>> openRowMajor({
    required String connectionId,
    required String query,
    required OdbcStreamingNativeOptions nativeStreamingOptions,
    Map<String, dynamic>? parameters,
    bool lazyStrings = false,
  }) {
    if (parameters != null && parameters.isNotEmpty) {
      return _service.streamQueryNamed(connectionId, query, parameters);
    }

    final batchedSource = _batchedQuerySource;
    final nativeConnectionId = int.tryParse(connectionId);
    if (batchedSource != null && nativeConnectionId != null && nativeConnectionId > 0) {
      return batchedSource.streamRowMajorQuery(
        nativeConnectionId,
        query,
        nativeStreamingOptions,
        lazyStrings: lazyStrings,
      );
    }

    return _service.streamQuery(connectionId, query);
  }
}
