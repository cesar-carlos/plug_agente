import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_adaptive_buffer_cache.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_options_builder.dart';

/// Computes [ConnectionAcquireOptions] for ODBC query execution.
///
/// Extracted from `OdbcDatabaseGateway` to centralize all option-shaping
/// concerns: the timeout-keyed options cache, transactional batch options,
/// adaptive buffer learning/hinting, and buffer-too-small detection.
final class OdbcConnectionOptionsResolver {
  OdbcConnectionOptionsResolver(
    this._settings, {
    OdbcAdaptiveBufferCache? adaptiveBufferCache,
  }) : _adaptiveBufferCache = adaptiveBufferCache ?? OdbcAdaptiveBufferCache();

  final IOdbcConnectionSettings _settings;
  final OdbcAdaptiveBufferCache _adaptiveBufferCache;
  final Map<String, ConnectionAcquireOptions> _cache = <String, ConnectionAcquireOptions>{};

  /// Default options (no explicit query timeout).
  ConnectionAcquireOptions get defaultOptions => forTimeout(null);

  /// Options for a query, optionally bounded by [timeout]. Cached per
  /// (timeout, login timeout, buffer) tuple to avoid rebuilding on hot paths.
  ConnectionAcquireOptions forTimeout(Duration? timeout) {
    final key = [
      timeout?.inMilliseconds ?? 0,
      _settings.loginTimeoutSeconds,
      _settings.maxResultBufferMb,
    ].join(':');
    return _cache.putIfAbsent(
      key,
      () {
        if (timeout == null) {
          return OdbcConnectionOptionsBuilder.forQueryExecution(_settings);
        }
        return OdbcConnectionOptionsBuilder.forQueryExecutionWithTimeout(
          _settings,
          queryTimeout: timeout,
        );
      },
    );
  }

  /// Options for transactional batch connections.
  ///
  /// Uses [OdbcConnectionOptionsBuilder.forTransactionalBatch] which sets
  /// `autoReconnectOnConnectionLost` to false, preventing silent transaction
  /// loss if the connection drops mid-transaction.
  ConnectionAcquireOptions transactionalForTimeout(Duration? timeout) {
    return OdbcConnectionOptionsBuilder.forTransactionalBatch(
      _settings,
      queryTimeout: timeout,
    );
  }

  /// Builds options with an expanded result buffer after a "buffer too small"
  /// driver error, preserving the other [baseOptions] fields.
  ConnectionAcquireOptions expandedFor(
    Object error, {
    required ConnectionAcquireOptions baseOptions,
    required int currentBufferBytes,
  }) {
    final expandedBufferBytes = OdbcGatewayBufferExpansion.calculateExpandedBufferBytes(
      currentBufferBytes: currentBufferBytes,
      errorMessage: bufferExpansionErrorMessage(error),
    );
    final baseInitialBufferBytes =
        baseOptions.initialResultBufferBytes ?? ConnectionConstants.defaultInitialResultBufferBytes;
    final initialResultBufferBytes = baseInitialBufferBytes < expandedBufferBytes
        ? baseInitialBufferBytes
        : expandedBufferBytes;

    developer.log(
      'Expanding max result buffer for retry: '
      '$currentBufferBytes -> $expandedBufferBytes bytes',
      name: 'database_gateway',
      level: 800,
    );

    return ConnectionAcquireOptions(
      loginTimeout: baseOptions.loginTimeout,
      queryTimeout: baseOptions.queryTimeout,
      maxResultBufferBytes: expandedBufferBytes,
      initialResultBufferBytes: initialResultBufferBytes,
      autoReconnectOnConnectionLost: baseOptions.autoReconnectOnConnectionLost,
      maxReconnectAttempts: baseOptions.maxReconnectAttempts,
      reconnectBackoff: baseOptions.reconnectBackoff,
    );
  }

  /// Returns options seeded with a previously learned buffer size for the
  /// (connectionString, sql) pair, or null when there is no hint.
  ConnectionAcquireOptions? hintedFor({
    required String connectionString,
    required String sql,
    required ConnectionAcquireOptions baseOptions,
  }) {
    final hintedBufferBytes = _adaptiveBufferCache.lookup(
      connectionString: connectionString,
      sql: sql,
    );
    if (hintedBufferBytes == null) {
      return null;
    }

    final initialBufferBytes =
        baseOptions.initialResultBufferBytes ?? ConnectionConstants.defaultInitialResultBufferBytes;
    return ConnectionAcquireOptions(
      loginTimeout: baseOptions.loginTimeout,
      queryTimeout: baseOptions.queryTimeout,
      maxResultBufferBytes: hintedBufferBytes,
      initialResultBufferBytes: initialBufferBytes < hintedBufferBytes ? initialBufferBytes : hintedBufferBytes,
      autoReconnectOnConnectionLost: baseOptions.autoReconnectOnConnectionLost,
      maxReconnectAttempts: baseOptions.maxReconnectAttempts,
      reconnectBackoff: baseOptions.reconnectBackoff,
    );
  }

  /// Records an expanded buffer size for future hinting after a driver
  /// "buffer too small" error.
  void rememberExpandedBuffer({
    required String connectionString,
    required String sql,
    required int currentBufferBytes,
    required Object error,
  }) {
    _adaptiveBufferCache.rememberExpandedBuffer(
      connectionString: connectionString,
      sql: sql,
      currentBufferBytes: currentBufferBytes,
      errorMessage: bufferExpansionErrorMessage(error),
    );
  }

  /// True when [error] indicates the result buffer was too small.
  bool isBufferTooSmallError(Object error) {
    if (error is domain.Failure && error.context['reason'] == OdbcContextConstants.bufferTooSmallReason) {
      return true;
    }
    if (error is domain.Failure && OdbcGatewayBufferExpansion.messageIndicatesBufferTooSmall(error.message)) {
      return true;
    }
    return OdbcGatewayBufferExpansion.messageIndicatesBufferTooSmall(
      bufferExpansionErrorMessage(error),
    );
  }

  /// Prefers the raw ODBC driver message from a [domain.Failure] context (which
  /// carries the byte-size hint the expansion parser needs) over the generic
  /// failure message.
  String bufferExpansionErrorMessage(Object error) {
    if (error is domain.Failure) {
      final rawOdbcMessage = error.context['odbc_message'];
      if (rawOdbcMessage is String && rawOdbcMessage.trim().isNotEmpty) {
        return rawOdbcMessage;
      }
    }
    return OdbcErrorInspector.message(error);
  }
}
