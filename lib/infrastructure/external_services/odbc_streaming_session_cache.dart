import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_odbc_streaming_session_cache.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_string_driver_hint.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_disconnect_tracker.dart';
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
/// the driver family supports columnar streaming (PostgreSQL). SQL Anywhere and
/// SQL Server stay on connect/disconnect per stream.
///
/// Evictions on [tryTake] stay queued so checkout stays synchronous. [offer]
/// and [drainCachedSessions] await those disconnects so handles are not leaked.
/// Timed-out disconnects stay tracked until the native call completes.
final class OdbcStreamingSessionCache implements IOdbcStreamingSessionCache {
  OdbcStreamingSessionCache({
    Duration? ttl,
    int? maxEntries,
    DateTime Function()? clock,
    OdbcStreamingSessionDisconnect? disconnectConnection,
    odbc.OdbcService? odbcService,
    OdbcStreamingDisconnectTracker? disconnectTracker,
  }) : _ttl = ttl ?? ConnectionConstants.streamingConnectReuseTtl,
       _maxEntries = maxEntries ?? ConnectionConstants.streamingConnectReuseMaxEntries,
       _clock = clock ?? DateTime.now,
       _disconnectConnection =
           disconnectConnection ??
           (odbcService == null ? null : (connectionId) => odbcService.disconnect(connectionId)),
       _disconnectTracker = disconnectTracker ?? OdbcStreamingDisconnectTracker();

  final Duration _ttl;
  final int _maxEntries;
  final DateTime Function() _clock;
  final OdbcStreamingSessionDisconnect? _disconnectConnection;
  final OdbcStreamingDisconnectTracker _disconnectTracker;
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
      _enqueueDisconnect(cached.connectionId);
      return null;
    }
    return cached.connectionId;
  }

  Future<bool> offer({
    required String connectionString,
    required String connectionId,
  }) async {
    if (!ConnectionConstants.streamingConnectReuseEnabled) {
      return false;
    }
    if (!connectionStringEligibleForStreamingConnectReuse(connectionString)) {
      return false;
    }
    if (connectionId.isEmpty) {
      return false;
    }

    final evictedIds = <String>[
      ..._evictExpired(),
      if (_entries.length >= _maxEntries && !_entries.containsKey(connectionString)) ..._evictOldest(),
    ];

    final previous = _entries[connectionString];
    if (previous != null && previous.connectionId != connectionId) {
      evictedIds.add(previous.connectionId);
    }

    _entries[connectionString] = _CachedStreamingSession(
      connectionId: connectionId,
      cachedAt: _clock(),
    );
    await _disconnectAll(evictedIds);
    return true;
  }

  @override
  void invalidate({String? connectionString}) {
    if (connectionString == null) {
      final connectionIds = _entries.values.map((entry) => entry.connectionId).toList(growable: false);
      _entries.clear();
      connectionIds.forEach(_enqueueDisconnect);
      return;
    }
    final removed = _entries.remove(connectionString);
    if (removed != null) {
      _enqueueDisconnect(removed.connectionId);
    }
  }

  @override
  Future<Result<void>> drainCachedSessions() async {
    final connectionIds = _entries.values.map((entry) => entry.connectionId).toList(growable: false);
    _entries.clear();

    final disconnect = _disconnectConnection;
    if (disconnect == null) {
      return _finishDrain(const <Object>[]);
    }

    final errors = <Object>[];
    for (final connectionId in connectionIds) {
      final result = await _disconnectTracked(connectionId);
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
    return _finishDrain(errors);
  }

  int get entryCount => _entries.length;

  int get inFlightDisconnectCount => _disconnectTracker.inFlightCount;

  List<String> _evictExpired() {
    if (_entries.isEmpty) {
      return const <String>[];
    }
    final now = _clock();
    final expiredIds = <String>[];
    _entries.removeWhere((_, entry) {
      final expired = now.difference(entry.cachedAt) >= _ttl;
      if (expired) {
        expiredIds.add(entry.connectionId);
      }
      return expired;
    });
    return expiredIds;
  }

  List<String> _evictOldest() {
    if (_entries.isEmpty) {
      return const <String>[];
    }
    var oldestKey = _entries.keys.first;
    var oldestAt = _entries[oldestKey]!.cachedAt;
    for (final entry in _entries.entries) {
      if (entry.value.cachedAt.isBefore(oldestAt)) {
        oldestKey = entry.key;
        oldestAt = entry.value.cachedAt;
      }
    }
    final removed = _entries.remove(oldestKey);
    if (removed == null) {
      return const <String>[];
    }
    return <String>[removed.connectionId];
  }

  void _enqueueDisconnect(String connectionId) {
    unawaited(_disconnectTracked(connectionId));
  }

  Future<void> _disconnectAll(Iterable<String> connectionIds) async {
    for (final connectionId in connectionIds) {
      await _disconnectTracked(connectionId);
    }
  }

  Future<Result<void>> _disconnectTracked(String connectionId) async {
    final disconnect = _disconnectConnection;
    if (disconnect == null || connectionId.isEmpty) {
      return const Success(unit);
    }
    return _disconnectTracker.run(
      connectionId: connectionId,
      disconnect: disconnect,
    );
  }

  Future<Result<void>> _finishDrain(List<Object> errors) async {
    await _disconnectTracker.drain(timeout: _disconnectTracker.observedTimeout);
    final remaining = List<Object>.of(errors);
    if (_disconnectTracker.inFlightCount > 0) {
      remaining.add(
        domain.ConnectionFailure.withContext(
          message: 'One or more streaming disconnects are still in flight after drain',
          context: {
            'reason': OdbcContextConstants.streamDisconnectStillInFlightReason,
            'in_flight': _disconnectTracker.inFlightCount,
            'discarded': true,
          },
        ),
      );
    }

    if (remaining.isEmpty) {
      return const Success(unit);
    }

    if (remaining.length == 1 && remaining.first is domain.Failure) {
      return Failure(remaining.first as domain.Failure);
    }

    final messages = remaining.map((error) => error is domain.Failure ? error.message : error.toString()).join('; ');
    return Failure(
      domain.ConnectionFailure.withContext(
        message: 'Failed to disconnect one or more cached streaming sessions: $messages',
        cause: remaining.first,
        context: {
          'reason': OdbcContextConstants.poolErrorReason,
          'operation': 'streaming_session_cache_drain',
          'error_count': remaining.length,
        },
      ),
    );
  }
}

bool connectionStringEligibleForStreamingConnectReuse(String connectionString) {
  return !connectionStringPrefersRowMajorStreaming(connectionString);
}
