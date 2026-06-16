import 'dart:math';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/config/odbc_recommended_options_merger.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_options_builder.dart';

/// Builds ODBC connection options tuned for streaming workloads.
final class OdbcStreamingConnectionOptionsBuilder {
  OdbcStreamingConnectionOptionsBuilder({
    required IOdbcConnectionSettings settings,
    OdbcProfileRecommendedOptions? recommendedOptions,
  }) : _settings = settings,
       _recommendedOptions = recommendedOptions;

  final IOdbcConnectionSettings _settings;
  final OdbcProfileRecommendedOptions? _recommendedOptions;

  ConnectionOptions build(
    int chunkSizeBytes, {
    int? hintedBufferBytes,
    Duration? queryTimeout,
    int? maxResultBufferBytes,
    bool lazyStrings = false,
  }) {
    final normalizedChunkSize = max(chunkSizeBytes, 64 * 1024);
    final resolvedMaxResultBufferBytes =
        maxResultBufferBytes ??
        max(
          normalizedChunkSize,
          max(
            hintedBufferBytes ?? 0,
            OdbcConnectionOptionsBuilder.clampedMaxResultBufferMb(_settings) * 1024 * 1024,
          ),
        );
    final initialResultBufferBytes = min(
      ConnectionConstants.defaultInitialResultBufferBytes,
      resolvedMaxResultBufferBytes,
    );

    final plugAcquireOptions = ConnectionAcquireOptions(
      loginTimeout: Duration(seconds: _settings.loginTimeoutSeconds),
      queryTimeout: queryTimeout ?? ConnectionConstants.defaultStreamingQueryTimeout,
      maxResultBufferBytes: resolvedMaxResultBufferBytes,
      initialResultBufferBytes: initialResultBufferBytes,
      autoReconnectOnConnectionLost: true,
      maxReconnectAttempts: ConnectionConstants.defaultMaxReconnectAttempts,
      reconnectBackoff: ConnectionConstants.defaultReconnectBackoff,
    );
    final recommended = _recommendedOptions?.connection;
    if (recommended != null) {
      return OdbcRecommendedOptionsMerger.mergeConnectionOptions(
        plugOptions: plugAcquireOptions,
        recommended: recommended,
        lazyStrings: lazyStrings,
      );
    }

    return ConnectionOptions(
      loginTimeout: plugAcquireOptions.loginTimeout,
      queryTimeout: plugAcquireOptions.queryTimeout,
      maxResultBufferBytes: plugAcquireOptions.maxResultBufferBytes,
      initialResultBufferBytes: plugAcquireOptions.initialResultBufferBytes,
      autoReconnectOnConnectionLost: plugAcquireOptions.autoReconnectOnConnectionLost ?? true,
      maxReconnectAttempts: plugAcquireOptions.maxReconnectAttempts,
      reconnectBackoff: plugAcquireOptions.reconnectBackoff,
      lazyStrings: lazyStrings,
    );
  }
}
