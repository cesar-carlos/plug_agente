import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/repositories/i_odbc_worker_runtime_recovery_port.dart';
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
  final ListQueue<OdbcEvent> _recentEvents = ListQueue<OdbcEvent>();
  late final StreamSubscription<OdbcEvent> _subscription;

  static const String _logName = 'odbc_event_bridge';
  static const int _previewMaxLength = 80;
  static const int _previewTruncatedLength = 77;

  /// Returns the most recent events captured by the bridge, newest first.
  /// Bounded to [kOdbcEventBridgeMaxRecentEvents] by default; older events
  /// are evicted automatically. Safe to read while events arrive: the
  /// returned list is an immutable snapshot.
  List<OdbcEvent> get recentEvents => UnmodifiableListView<OdbcEvent>(
    _recentEvents.toList(growable: false),
  );

  void _handleEvent(OdbcEvent event) {
    _trackRecent(event);
    switch (event) {
      case ConnectionLost(:final connectionId, :final reason, :final timestamp):
        _metrics?.recordOdbcEventConnectionLost();
        developer.log(
          'ODBC connection lost',
          name: _logName,
          level: 900,
          time: timestamp,
          error: <String, Object?>{
            'connection_id': connectionId,
            'reason_type': reason.runtimeType.toString(),
            'reason_message': reason.toString(),
          },
        );
      case AutoReconnectAttempted(:final connectionId, :final attempt, :final maxAttempts, :final timestamp):
        _metrics?.recordOdbcEventAutoReconnectAttempted();
        developer.log(
          'ODBC auto-reconnect attempt $attempt/$maxAttempts',
          name: _logName,
          level: 800,
          time: timestamp,
          error: <String, Object?>{
            'connection_id': connectionId,
            'attempt': attempt,
            'max_attempts': maxAttempts,
          },
        );
      case WorkerRecovered(:final timestamp):
        _metrics?.recordOdbcEventWorkerRecovered();
        unawaited(() async {
        try {
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
      case PoolResize(:final poolId, :final oldSize, :final newSize, :final timestamp):
        _metrics?.recordOdbcEventPoolResize();
        developer.log(
          'ODBC native pool resize $oldSize -> $newSize',
          name: _logName,
          level: 800,
          time: timestamp,
          error: <String, Object?>{
            'pool_id': poolId,
            'old_size': oldSize,
            'new_size': newSize,
          },
        );
      case SlowQueryDetected(:final connectionId, :final sql, :final durationMs, :final timestamp):
        _metrics?.recordOdbcEventSlowQueryDetected();
        final preview = sql.length > _previewMaxLength ? '${sql.substring(0, _previewTruncatedLength)}...' : sql;
        developer.log(
          'ODBC slow query (${durationMs}ms): $preview',
          name: _logName,
          level: 900,
          time: timestamp,
          error: <String, Object?>{
            'connection_id': connectionId,
            'duration_ms': durationMs,
            'sql_preview': preview,
          },
        );
    }
  }

  void _trackRecent(OdbcEvent event) {
    _recentEvents.addFirst(event);
    while (_recentEvents.length > _maxRecentEvents) {
      _recentEvents.removeLast();
    }
  }

  Future<void> dispose() async {
    await _subscription.cancel();
  }
}
