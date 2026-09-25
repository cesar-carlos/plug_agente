import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/repositories/i_odbc_worker_runtime_recovery_port.dart';
import 'package:plug_agente/infrastructure/logging/odbc_resilience_log.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

/// Maximum number of recent events kept in the ring buffer exposed by
/// [OdbcEventBridge.recentEvents]. Bounded so the bridge stays cheap to
/// poll from diagnostic snapshots while still showing enough history to
/// correlate a recent incident.
const int kOdbcEventBridgeMaxRecentEvents = 32;

/// Listens to ODBC runtime events emitted by [IAdminService.events] and
/// fans them out to structured logging, a quantitative [MetricsCollector],
/// and a bounded in-memory ring buffer for diagnostic snapshots.
///
/// Depends on the narrower [IAdminService] sub-interface (ISP) — only the
/// `events` stream is needed from the package.
final class OdbcEventBridge {
  OdbcEventBridge({
    required IAdminService adminService,
    MetricsCollector? metrics,
    IOdbcWorkerRuntimeRecoveryPort? workerRecoveryPort,
    int maxRecentEvents = kOdbcEventBridgeMaxRecentEvents,
  }) : _metrics = metrics,
       _workerRecoveryPort = workerRecoveryPort,
       _maxRecentEvents = maxRecentEvents > 0 ? maxRecentEvents : kOdbcEventBridgeMaxRecentEvents {
    _subscription = adminService.events.listen(_handleEvent);
  }

  final MetricsCollector? _metrics;
  final IOdbcWorkerRuntimeRecoveryPort? _workerRecoveryPort;
  final int _maxRecentEvents;
  final ListQueue<Map<String, Object?>> _recentEvents = ListQueue<Map<String, Object?>>();
  late final StreamSubscription<OdbcEvent> _subscription;
  bool _isDisposed = false;

  static const String _logName = 'odbc_event_bridge';

  /// Returns the most recent events captured by the bridge, newest first.
  /// Bounded to [kOdbcEventBridgeMaxRecentEvents] by default; older events
  /// are evicted automatically. Safe to read while events arrive: the
  /// returned list is an immutable snapshot.
  List<Map<String, Object?>> get recentEvents => UnmodifiableListView<Map<String, Object?>>(
    _recentEvents.toList(growable: false),
  );

  void _handleEvent(OdbcEvent event) {
    if (_isDisposed) {
      return;
    }
    _trackRecent(event);
    switch (event) {
      case ConnectionLost(:final timestamp):
        _metrics?.recordOdbcEventConnectionLost();
        OdbcResilienceLog.warning(event: 'connection_lost', reason: 'connection_lost');
        developer.log(
          'ODBC connection lost',
          name: _logName,
          level: 900,
          time: timestamp,
          error: _safeEvent(event),
        );
      case AutoReconnectAttempted(:final attempt, :final maxAttempts, :final timestamp):
        _metrics?.recordOdbcEventAutoReconnectAttempted();
        developer.log(
          'ODBC auto-reconnect attempt $attempt/$maxAttempts',
          name: _logName,
          level: 800,
          time: timestamp,
          error: _safeEvent(event),
        );
      case WorkerRecovered(:final timestamp):
        _metrics?.recordOdbcEventWorkerRecovered();
        OdbcResilienceLog.operational(event: 'worker_recovered');
        unawaited(() async {
          try {
            if (_isDisposed) {
              return;
            }
            await _workerRecoveryPort?.recoverAfterNativeWorkerCrash();
          } on Object catch (error, stackTrace) {
            developer.log(
              'ODBC worker recovery failed after native worker crash',
              name: _logName,
              level: 1000,
              time: timestamp,
              error: error,
              stackTrace: stackTrace,
            );
          }
        }());
        developer.log(
          'ODBC async worker recovered after crash',
          name: _logName,
          level: 900,
          time: timestamp,
        );
      case PoolResize(:final oldSize, :final newSize, :final timestamp):
        _metrics?.recordOdbcEventPoolResize();
        developer.log(
          'ODBC native pool resize $oldSize -> $newSize',
          name: _logName,
          level: 800,
          time: timestamp,
          error: _safeEvent(event),
        );
      case SlowQueryDetected(:final durationMs, :final timestamp):
        _metrics?.recordOdbcEventSlowQueryDetected();
        developer.log(
          'ODBC slow query detected (${durationMs}ms)',
          name: _logName,
          level: 900,
          time: timestamp,
          error: _safeEvent(event),
        );
    }
  }

  void _trackRecent(OdbcEvent event) {
    _recentEvents.addFirst(_safeEvent(event));
    while (_recentEvents.length > _maxRecentEvents) {
      _recentEvents.removeLast();
    }
  }

  static Map<String, Object?> _safeEvent(OdbcEvent event) {
    final base = <String, Object?>{
      'kind': event.runtimeType.toString(),
      'timestamp': event.timestamp.toIso8601String(),
    };
    switch (event) {
      case ConnectionLost(:final reason):
        base['reason_code'] = reason.runtimeType.toString();
      case AutoReconnectAttempted(:final attempt, :final maxAttempts):
        base['attempt'] = attempt;
        base['max_attempts'] = maxAttempts;
      case WorkerRecovered():
        break;
      case PoolResize(:final oldSize, :final newSize):
        base['old_size'] = oldSize;
        base['new_size'] = newSize;
      case SlowQueryDetected(:final sql, :final durationMs):
        base['duration_ms'] = durationMs;
        base['sql_kind'] = _sqlKind(sql);
    }
    return Map<String, Object?>.unmodifiable(base);
  }

  static String _sqlKind(String sql) {
    final normalized = sql.trimLeft();
    if (normalized.isEmpty) {
      return 'unknown';
    }
    return normalized.split(RegExp(r'\s+')).first.toLowerCase();
  }

  Future<void> dispose() async {
    _isDisposed = true;
    await _subscription.cancel();
  }
}
