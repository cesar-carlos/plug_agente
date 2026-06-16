import 'dart:async';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/repositories/i_odbc_worker_runtime_recovery_port.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_event_bridge.dart';

class _MockAdminService extends Mock implements IAdminService {}

class _MockWorkerRecoveryPort extends Mock implements IOdbcWorkerRuntimeRecoveryPort {}

void main() {
  group('OdbcEventBridge', () {
    late _MockAdminService adminService;
    late StreamController<OdbcEvent> controller;

    setUp(() {
      adminService = _MockAdminService();
      controller = StreamController<OdbcEvent>.broadcast(sync: true);
      when(() => adminService.events).thenAnswer((_) => controller.stream);
    });

    tearDown(() async {
      await controller.close();
    });

    test('should subscribe to events on construction', () {
      OdbcEventBridge(adminService: adminService);

      check(controller.hasListener).isTrue();
    });

    test('should handle every OdbcEvent variant without throwing', () async {
      final bridge = OdbcEventBridge(adminService: adminService);
      final timestamp = DateTime.utc(2026, 5, 27, 12);

      controller
        ..add(
          ConnectionLost(
            timestamp: timestamp,
            connectionId: 'conn-1',
            reason: const ConnectionError(message: 'network'),
          ),
        )
        ..add(
          AutoReconnectAttempted(
            timestamp: timestamp,
            connectionId: 'conn-1',
            attempt: 2,
            maxAttempts: 5,
          ),
        )
        ..add(WorkerRecovered(timestamp: timestamp))
        ..add(
          PoolResize(
            timestamp: timestamp,
            poolId: 42,
            oldSize: 4,
            newSize: 8,
          ),
        )
        ..add(
          SlowQueryDetected(
            timestamp: timestamp,
            connectionId: 'conn-1',
            sql: 'select * from very_large_table',
            durationMs: 1234,
          ),
        );

      await Future<void>.delayed(Duration.zero);
      await bridge.dispose();

      check(controller.hasListener).isFalse();
    });

    test('should truncate very long SQL previews', () async {
      final bridge = OdbcEventBridge(adminService: adminService);
      final timestamp = DateTime.utc(2026, 5, 27, 12);
      final longSql = 'select ${'col, ' * 200} from t';

      controller.add(
        SlowQueryDetected(
          timestamp: timestamp,
          connectionId: 'conn-1',
          sql: longSql,
          durationMs: 5000,
        ),
      );

      await Future<void>.delayed(Duration.zero);
      await bridge.dispose();
    });

    test('should release subscription on dispose', () async {
      final bridge = OdbcEventBridge(adminService: adminService);
      check(controller.hasListener).isTrue();

      await bridge.dispose();

      check(controller.hasListener).isFalse();
    });

    test('should record event counters on the MetricsCollector', () async {
      final metrics = MetricsCollector();
      final bridge = OdbcEventBridge(adminService: adminService, metrics: metrics);
      addTearDown(metrics.dispose);
      final timestamp = DateTime.utc(2026, 5, 27, 12);

      controller
        ..add(
          ConnectionLost(
            timestamp: timestamp,
            connectionId: 'conn-1',
            reason: const ConnectionError(message: 'net'),
          ),
        )
        ..add(WorkerRecovered(timestamp: timestamp))
        ..add(
          PoolResize(
            timestamp: timestamp,
            poolId: 42,
            oldSize: 4,
            newSize: 8,
          ),
        )
        ..add(
          AutoReconnectAttempted(
            timestamp: timestamp,
            connectionId: 'conn-1',
            attempt: 1,
            maxAttempts: 3,
          ),
        )
        ..add(
          SlowQueryDetected(
            timestamp: timestamp,
            connectionId: 'conn-1',
            sql: 'select 1',
            durationMs: 1234,
          ),
        );

      await Future<void>.delayed(Duration.zero);
      await bridge.dispose();

      final snapshot = metrics.getSnapshot();
      check(snapshot['odbc_event_connection_lost']).equals(1);
      check(snapshot['odbc_event_worker_recovered']).equals(1);
      check(snapshot['odbc_event_pool_resize']).equals(1);
      check(snapshot['odbc_event_auto_reconnect_attempted']).equals(1);
      check(snapshot['odbc_event_slow_query_detected']).equals(1);
    });

    test('should invoke worker recovery port on WorkerRecovered', () async {
      final recoveryPort = _MockWorkerRecoveryPort();
      when(recoveryPort.recoverAfterNativeWorkerCrash).thenAnswer((_) async {});
      final bridge = OdbcEventBridge(
        adminService: adminService,
        workerRecoveryPort: recoveryPort,
      );
      final timestamp = DateTime.utc(2026, 5, 27, 12);

      controller.add(WorkerRecovered(timestamp: timestamp));
      await Future<void>.delayed(Duration.zero);
      await bridge.dispose();

      verify(recoveryPort.recoverAfterNativeWorkerCrash).called(1);
    });

    test('should log worker recovery failures without throwing', () async {
      final recoveryPort = _MockWorkerRecoveryPort();
      when(recoveryPort.recoverAfterNativeWorkerCrash).thenThrow(StateError('recovery failed'));
      final bridge = OdbcEventBridge(
        adminService: adminService,
        workerRecoveryPort: recoveryPort,
      );
      final timestamp = DateTime.utc(2026, 5, 27, 12);

      controller.add(WorkerRecovered(timestamp: timestamp));
      await Future<void>.delayed(Duration.zero);
      await bridge.dispose();

      verify(recoveryPort.recoverAfterNativeWorkerCrash).called(1);
    });

    test('should expose newest events first via recentEvents (bounded ring)', () async {
      final bridge = OdbcEventBridge(adminService: adminService, maxRecentEvents: 3);
      final baseTimestamp = DateTime.utc(2026, 5, 27, 12);

      for (var i = 0; i < 5; i++) {
        controller.add(
          WorkerRecovered(timestamp: baseTimestamp.add(Duration(seconds: i))),
        );
      }
      await Future<void>.delayed(Duration.zero);

      final events = bridge.recentEvents;
      check(events.length).equals(3);
      check(events.first.timestamp).equals(baseTimestamp.add(const Duration(seconds: 4)));
      check(events.last.timestamp).equals(baseTimestamp.add(const Duration(seconds: 2)));

      await bridge.dispose();
    });
  });
}
