import 'dart:math';

import 'package:plug_agente/core/constants/connection_constants.dart';

/// Native ODBC streaming parameters propagated to `streamQueryBatched`.
class OdbcStreamingNativeOptions {
  const OdbcStreamingNativeOptions({
    required this.fetchSize,
    required this.nativeChunkSizeBytes,
    required this.maxResultBufferBytes,
  });

  factory OdbcStreamingNativeOptions.resolve({
    required int fetchSize,
    required int chunkSizeBytes,
    required int settingsMaxResultBufferMb,
    int? hintedBufferBytes,
  }) {
    final safeFetchSize = fetchSize > 0 ? fetchSize : odbcFastDefaultFetchSize;
    final normalizedChunkSize = max(chunkSizeBytes, minNativeChunkSizeBytes);
    final maxResultBufferBytes = max(
      normalizedChunkSize,
      max(
        hintedBufferBytes ?? 0,
        settingsMaxResultBufferMb * 1024 * 1024,
      ),
    );

    return OdbcStreamingNativeOptions(
      fetchSize: safeFetchSize,
      nativeChunkSizeBytes: normalizedChunkSize,
      maxResultBufferBytes: max(
        maxResultBufferBytes,
        ConnectionConstants.defaultInitialResultBufferBytes,
      ),
    );
  }

  static const int odbcFastDefaultFetchSize = 1000;
  static const int odbcFastDefaultNativeChunkSizeBytes = 64 * 1024;
  static const int minNativeChunkSizeBytes = 64 * 1024;

  /// Hub Socket.IO streaming workloads (single- and multi-result). Matches
  /// [ConnectionConstants.defaultStreamingChunkSizeKb] so streamFetch seeds a
  /// larger buffer than the package materialize default.
  static const int hubStreamingChunkSizeBytes =
      ConnectionConstants.defaultStreamingChunkSizeKb * 1024;

  /// Materialized multi-result RPC. Same 1 MiB seed as hub streaming so
  /// `streamQueryMultiBatches` does not start on the 64 KiB package default.
  static const int materializedMultiResultChunkSizeBytes = hubStreamingChunkSizeBytes;

  final int fetchSize;
  final int nativeChunkSizeBytes;
  final int maxResultBufferBytes;
}
