import 'dart:math';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';

/// Builds [ConnectionOptions] aligned with UI limits (8–128 MB) and safe
/// fallbacks when persisted settings are missing or invalid (e.g. 0 MB).
class OdbcConnectionOptionsBuilder {
  OdbcConnectionOptionsBuilder._();

  static const int minMaxResultBufferMb = 8;
  static const int maxMaxResultBufferMb = 128;

  static int clampedMaxResultBufferMb(IOdbcConnectionSettings settings) {
    final raw = settings.maxResultBufferMb;
    if (raw < minMaxResultBufferMb) {
      return ConnectionConstants.defaultMaxResultBufferBytes ~/ (1024 * 1024);
    }
    if (raw > maxMaxResultBufferMb) {
      return maxMaxResultBufferMb;
    }
    return raw;
  }

  /// Options for pooled / standard query execution (matches gateway defaults).
  static ConnectionOptions forQueryExecution(IOdbcConnectionSettings settings) {
    return forQueryExecutionWithTimeout(
      settings,
      queryTimeout: ConnectionConstants.defaultQueryTimeout,
    );
  }

  static ConnectionOptions forQueryExecutionWithTimeout(
    IOdbcConnectionSettings settings, {
    required Duration queryTimeout,
  }) {
    final mb = clampedMaxResultBufferMb(settings);
    final maxBytes = mb * 1024 * 1024;
    final initialBytes = min(
      ConnectionConstants.defaultInitialResultBufferBytes,
      maxBytes,
    );
    return ConnectionOptions(
      loginTimeout: Duration(seconds: settings.loginTimeoutSeconds),
      queryTimeout: queryTimeout,
      maxResultBufferBytes: maxBytes,
      initialResultBufferBytes: initialBytes,
      autoReconnectOnConnectionLost: true,
      maxReconnectAttempts: ConnectionConstants.defaultMaxReconnectAttempts,
      reconnectBackoff: ConnectionConstants.defaultReconnectBackoff,
    );
  }
}
