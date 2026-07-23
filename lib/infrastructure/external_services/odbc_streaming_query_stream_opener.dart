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
    final namedParameters = _namedParametersOrNull(parameters);
    final batchedSource = _batchedQuerySource;
    final nativeConnectionId = int.tryParse(connectionId);
    final canUseBatched =
        batchedSource != null && nativeConnectionId != null && nativeConnectionId > 0;

    if (canUseBatched) {
      return batchedSource.streamColumnarQuery(
        nativeConnectionId,
        query,
        nativeStreamingOptions,
        namedParameters: namedParameters,
      );
    }

    if (namedParameters != null) {
      return _service.streamQueryNamed(connectionId, query, namedParameters).map((result) => result.map(toTypedColumnar));
    }

    return _service.streamQueryColumnar(connectionId, query);
  }

  Stream<Result<QueryResult>> openRowMajor({
    required String connectionId,
    required String query,
    required OdbcStreamingNativeOptions nativeStreamingOptions,
    Map<String, dynamic>? parameters,
    bool lazyStrings = false,
  }) {
    final namedParameters = _namedParametersOrNull(parameters);
    final batchedSource = _batchedQuerySource;
    final nativeConnectionId = int.tryParse(connectionId);
    final canUseBatched =
        batchedSource != null && nativeConnectionId != null && nativeConnectionId > 0;

    if (canUseBatched) {
      return batchedSource.streamRowMajorQuery(
        nativeConnectionId,
        query,
        nativeStreamingOptions,
        lazyStrings: lazyStrings,
        namedParameters: namedParameters,
      );
    }

    if (namedParameters != null) {
      return _service.streamQueryNamed(connectionId, query, namedParameters);
    }

    return _service.streamQuery(connectionId, query);
  }

  Map<String, Object?>? _namedParametersOrNull(Map<String, dynamic>? parameters) {
    if (parameters == null || parameters.isEmpty) {
      return null;
    }
    return Map<String, Object?>.from(parameters);
  }
}
