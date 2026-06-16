import 'dart:math';

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';

/// Builds connection acquire options aligned with UI limits and safe fallbacks
/// when persisted settings are missing or invalid (e.g. 0 MB).
class OdbcConnectionOptionsBuilder {
  OdbcConnectionOptionsBuilder._();

  static int get minMaxResultBufferMb => ConnectionConstants.minMaxResultBufferMb;
  static int get maxMaxResultBufferMb => ConnectionConstants.maxMaxResultBufferMb;

  static int clampedMaxResultBufferMb(IOdbcConnectionSettings settings) {
    final raw = settings.maxResultBufferMb;
    if (raw < ConnectionConstants.minMaxResultBufferMb) {
      return ConnectionConstants.defaultMaxResultBufferBytes ~/ (1024 * 1024);
    }
    if (raw > ConnectionConstants.maxMaxResultBufferMb) {
      return ConnectionConstants.maxMaxResultBufferMb;
    }
    return raw;
  }

  /// Options for pooled / standard query execution (matches gateway defaults).
  static ConnectionAcquireOptions forQueryExecution(IOdbcConnectionSettings settings) {
    return forQueryExecutionWithTimeout(
      settings,
      queryTimeout: ConnectionConstants.defaultQueryTimeout,
    );
  }

  static ConnectionAcquireOptions forQueryExecutionWithTimeout(
    IOdbcConnectionSettings settings, {
    required Duration queryTimeout,
  }) {
    final mb = clampedMaxResultBufferMb(settings);
    final maxBytes = mb * 1024 * 1024;
    final initialBytes = min(
      ConnectionConstants.defaultInitialResultBufferBytes,
      maxBytes,
    );
    return ConnectionAcquireOptions(
      loginTimeout: Duration(seconds: settings.loginTimeoutSeconds),
      queryTimeout: queryTimeout,
      maxResultBufferBytes: maxBytes,
      initialResultBufferBytes: initialBytes,
      autoReconnectOnConnectionLost: true,
      maxReconnectAttempts: ConnectionConstants.defaultMaxReconnectAttempts,
      reconnectBackoff: ConnectionConstants.defaultReconnectBackoff,
    );
  }

  /// Options for transactional batch execution.
  ///
  /// Disables auto-reconnect to prevent silent transaction loss: if the
  /// connection drops mid-transaction and the driver auto-reconnects, the
  /// active transaction is gone but the calling code would continue with a
  /// stale transaction ID, leading to data integrity issues on commit.
  static ConnectionAcquireOptions forTransactionalBatch(
    IOdbcConnectionSettings settings, {
    Duration? queryTimeout,
  }) {
    final mb = clampedMaxResultBufferMb(settings);
    final maxBytes = mb * 1024 * 1024;
    final initialBytes = min(
      ConnectionConstants.defaultInitialResultBufferBytes,
      maxBytes,
    );
    return ConnectionAcquireOptions(
      loginTimeout: Duration(seconds: settings.loginTimeoutSeconds),
      queryTimeout: queryTimeout ?? ConnectionConstants.defaultTransactionalBatchTimeout,
      maxResultBufferBytes: maxBytes,
      initialResultBufferBytes: initialBytes,
      autoReconnectOnConnectionLost: false,
      maxReconnectAttempts: ConnectionConstants.defaultMaxReconnectAttempts,
      reconnectBackoff: ConnectionConstants.defaultReconnectBackoff,
    );
  }
}
