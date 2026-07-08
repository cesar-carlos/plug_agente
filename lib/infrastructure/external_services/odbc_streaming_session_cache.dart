import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_odbc_streaming_session_cache.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_string_driver_hint.dart';
import 'package:result_dart/result_dart.dart';

typedef OdbcStreamingSessionDisconnect = Future<Result<void>> Function(String connectionId);

class _CachedStreamingSession {
  const _CachedStreamingSession({
    required this.connectionId,
    required this.cachedAt,
  });

  final String connectionId;
  final DateTime cachedAt;
}

/// Short-TTL cache of idle streaming ODBC connections keyed by connection string.
///
/// Reuse skips the ODBC handshake on back-to-back streams for the same DSN when
/// the driver family supports columnar streaming (SQL Server / PostgreSQL).
/// SQL Anywhere stays on connect/disconnect per stream.
final class OdbcStreamingSessionCache implements IOdbcStreamingSessionCache {
  OdbcStreamingSessionCache({
    Duration? ttl,
    int? maxEntries,
    DateTime Function()? clock,
    OdbcStreamingSessionDisconnect? disconnectConnection,
    odbc.OdbcService? odbcService,
  }) : _ttl = ttl ?? ConnectionConstants.streamingConnectReuseTtl,
       _maxEntries = maxEntries ?? ConnectionConstants.streamingConnectReuseMaxEntries,
       _clock = clock ?? DateTime.now,
       _disconnectConnection =
           disconnectConnection ??
           (odbcService == null ? null : (String connectionId) => odbcService.disconnect(connectionId));

  final Duration _ttl;
  final int _maxEntries;
  final DateTime Function() _clock;
  final OdbcStreamingSessionDisconnect? _disconnectConnection;
  final Map<String, _CachedStreamingSession> _entries = <String, _CachedStreamingSession>{};

  String? tryTake(String connectionString) {
    if (!ConnectionConstants.streamingConnectReuseEnabled) {
      return null;
    }
    if (!connectionStringEligibleForStreamingConnectReuse(connectionString)) {
      return null;
    }

    final now = _clock();
    final cached = _entries.remove(connectionString);
    if (cached == null) {
      return null;
    }
    if (now.difference(cached.cachedAt) >= _ttl) {
      return null;
    }
    return cached.connectionId;
  }

  bool offer({
    required String connectionString,
    required String connectionId,
  }) {
    if (!ConnectionConstants.streamingConnectReuseEnabled) {
      return false;
    }
    if (!connectionStringEligibleForStreamingConnectReuse(connectionString)) {
      return false;
    }
    if (connectionId.isEmpty) {
      return false;
    }

    _evictExpired();
    if (_entries.length >= _maxEntries && !_entries.containsKey(connectionString)) {
      _evictOldest();
    }

    _entries[connectionString] = _CachedStreamingSession(
      connectionId: connectionId,
      cachedAt: _clock(),
    );
    return true;
  }

  @override
  void invalidate({String? connectionString}) {
    if (connectionString == null) {
      _entries.clear();
      return;
    }
    _entries.remove(connectionString);
  }

  @override
  Future<Result<void>> drainCachedSessions() async {
    if (_entries.isEmpty) {
      return const Success(unit);
    }

    final connectionIds = _entries.values.map((entry) => entry.connectionId).toList(growable: false);
    _entries.clear();

    final disconnect = _disconnectConnection;
    if (disconnect == null) {
      return const Success(unit);
    }

    final errors = <Object>[];
    for (final connectionId in connectionIds) {
      final result = await disconnect(connectionId);
      result.fold(
        (_) {},
        (error) {
          errors.add(error);
          developer.log(
            'Failed to disconnect cached streaming session $connectionId during drain',
            name: 'odbc_streaming_session_cache',
            level: 900,
            error: error,
          );
        },
      );
    }

    if (errors.isEmpty) {
      return const Success(unit);
    }

    if (errors.length == 1 && errors.first is domain.Failure) {
      return Failure(errors.first as domain.Failure);
    }

    final messages = errors.map((error) => error is domain.Failure ? error.message : error.toString()).join('; ');
    return Failure(
      domain.ConnectionFailure.withContext(
        message: 'Failed to disconnect one or more cached streaming sessions: $messages',
        cause: errors.first,
        context: {
          'reason': OdbcContextConstants.poolErrorReason,
          'operation': 'streaming_session_cache_drain',
          'error_count': errors.length,
        },
      ),
    );
  }

  int get entryCount => _entries.length;

  void _evictExpired() {
    if (_entries.isEmpty) {
      return;
    }
    final now = _clock();
    _entries.removeWhere(
      (_, entry) => now.difference(entry.cachedAt) >= _ttl,
    );
  }

  void _evictOldest() {
    if (_entries.isEmpty) {
      return;
    }
    var oldestKey = _entries.keys.first;
    var oldestAt = _entries[oldestKey]!.cachedAt;
    for (final entry in _entries.entries) {
      if (entry.value.cachedAt.isBefore(oldestAt)) {
        oldestKey = entry.key;
        oldestAt = entry.value.cachedAt;
      }
    }
    _entries.remove(oldestKey);
  }
}

bool connectionStringEligibleForStreamingConnectReuse(String connectionString) {
  return !connectionStringPrefersRowMajorStreaming(connectionString);
}
