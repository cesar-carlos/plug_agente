import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_odbc_streaming_session_cache.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_string_driver_hint.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_disconnect_tracker.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

typedef OdbcStreamingSessionDisconnect = Future<Result<void>> Function(String connectionId);

class _CachedStreamingSession {
  const _CachedStreamingSession({
    required this.connectionId,
    required this.cachedAt,
    this.reservation,
  });

  final String connectionId;
  final DateTime cachedAt;
  final DirectOdbcConnectionLease? reservation;
}

/// A cached physical session and its retained direct-connection reservation.
final class OdbcCachedStreamingSession {
  const OdbcCachedStreamingSession({
    required this.connectionId,
    this.reservation,
  });

  final String connectionId;
  final DirectOdbcConnectionLease? reservation;
}

/// Short-TTL cache of idle streaming ODBC connections keyed by connection string.
///
/// A cached connection retains its limiter reservation. This makes physical
/// connection reuse count against the same capacity as active streams; the
/// lease is transferred on reuse and is released only after native disconnect
/// actually completes.
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
  int _maxEntries;
  final DateTime Function() _clock;
  final OdbcStreamingSessionDisconnect? _disconnectConnection;
  final OdbcStreamingDisconnectTracker _disconnectTracker;
  final Map<String, _CachedStreamingSession> _entries = <String, _CachedStreamingSession>{};

  String? tryTake(String connectionString) => tryTakeSession(connectionString)?.connectionId;

  OdbcCachedStreamingSession? tryTakeSession(String connectionString) {
    if (!ConnectionConstants.streamingConnectReuseEnabled ||
        !connectionStringEligibleForStreamingConnectReuse(connectionString)) {
      return null;
    }
    final cached = _entries.remove(connectionString);
    if (cached == null) {
      return null;
    }
    if (_clock().difference(cached.cachedAt) >= _ttl) {
      _enqueueDisconnect(cached);
      return null;
    }
    return OdbcCachedStreamingSession(
      connectionId: cached.connectionId,
      reservation: cached.reservation,
    );
  }

  Future<bool> offer({
    required String connectionString,
    required String connectionId,
    DirectOdbcConnectionLease? reservation,
  }) async {
    if (!ConnectionConstants.streamingConnectReuseEnabled ||
        !connectionStringEligibleForStreamingConnectReuse(connectionString) ||
        connectionId.isEmpty ||
        _maxEntries <= 0) {
      return false;
    }

    final evicted = <_CachedStreamingSession>[
      ..._evictExpired(),
      if (_entries.length >= _maxEntries && !_entries.containsKey(connectionString)) ..._evictOldest(),
    ];
    final previous = _entries[connectionString];
    if (previous != null && previous.connectionId != connectionId) {
      evicted.add(previous);
    }
    _entries[connectionString] = _CachedStreamingSession(
      connectionId: connectionId,
      cachedAt: _clock(),
      reservation: reservation,
    );
    await _disconnectAll(evicted);
    return true;
  }

  /// Keeps one direct slot free for a fresh stream. Shrinking the limit evicts
  /// excess sessions immediately, while their lease remains held until native
  /// cleanup has finished.
  void setCapacityLimit(int maxEntries) {
    _maxEntries = maxEntries < 0 ? 0 : maxEntries;
    while (_entries.length > _maxEntries) {
      _evictOldest().forEach(_enqueueDisconnect);
    }
  }

  @override
  void invalidate({String? connectionString}) {
    if (connectionString == null) {
      final sessions = _entries.values.toList(growable: false);
      _entries.clear();
      sessions.forEach(_enqueueDisconnect);
      return;
    }
    final session = _entries.remove(connectionString);
    if (session != null) {
      _enqueueDisconnect(session);
    }
  }

  @override
  Future<Result<void>> drainCachedSessions() async {
    final sessions = _entries.values.toList(growable: false);
    _entries.clear();
    final disconnect = _disconnectConnection;
    if (disconnect == null) {
      for (final session in sessions) {
        session.reservation?.release();
      }
      return _finishDrain(const <Object>[]);
    }

    final errors = <Object>[];
    for (final session in sessions) {
      final result = await _disconnectTracked(session);
      result.fold(
        (_) {},
        (error) {
          errors.add(error);
          developer.log(
            'Failed to disconnect a cached streaming session during drain',
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

  List<_CachedStreamingSession> _evictExpired() {
    if (_entries.isEmpty) {
      return const <_CachedStreamingSession>[];
    }
    final expired = <_CachedStreamingSession>[];
    final now = _clock();
    _entries.removeWhere((_, entry) {
      final isExpired = now.difference(entry.cachedAt) >= _ttl;
      if (isExpired) {
        expired.add(entry);
      }
      return isExpired;
    });
    return expired;
  }

  List<_CachedStreamingSession> _evictOldest() {
    if (_entries.isEmpty) {
      return const <_CachedStreamingSession>[];
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
    return removed == null ? const <_CachedStreamingSession>[] : <_CachedStreamingSession>[removed];
  }

  void _enqueueDisconnect(_CachedStreamingSession session) {
    unawaited(_disconnectTracked(session));
  }

  Future<void> _disconnectAll(Iterable<_CachedStreamingSession> sessions) async {
    for (final session in sessions) {
      await _disconnectTracked(session);
    }
  }

  Future<Result<void>> _disconnectTracked(_CachedStreamingSession session) async {
    final disconnect = _disconnectConnection;
    if (disconnect == null || session.connectionId.isEmpty) {
      session.reservation?.release();
      return const Success(unit);
    }
    return _disconnectTracker.run(
      connectionId: session.connectionId,
      disconnect: disconnect,
      onComplete: session.reservation?.release,
    );
  }

  Future<Result<void>> _finishDrain(List<Object> errors) async {
    await _disconnectTracker.drain(timeout: _disconnectTracker.observedTimeout);
    final remaining = List<Object>.of(errors);
    if (_disconnectTracker.inFlightCount > 0) {
      remaining.add(
        domain.ConnectionFailure.withContext(
          message: 'One or more streaming disconnects are still in flight after drain',
          context: <String, Object?>{
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
    return Failure(
      domain.ConnectionFailure.withContext(
        message: 'Failed to disconnect one or more cached streaming sessions',
        cause: remaining.first,
        context: <String, Object?>{
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
