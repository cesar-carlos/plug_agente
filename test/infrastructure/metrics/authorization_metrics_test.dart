import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/authorization_metric.dart';
import 'package:plug_agente/domain/entities/authorization_metrics_summary.dart';
import 'package:plug_agente/infrastructure/metrics/authorization_metrics.dart';

void main() {
  group('AuthorizationMetric', () {
    test('toJson should include all fields when present', () {
      final metric = AuthorizationMetric(
        timestamp: DateTime.utc(2025, 3, 12, 10),
        authorized: true,
        clientId: 'client-1',
        operation: 'read',
        resource: 'dbo.users',
      );

      final json = metric.toJson();

      check(json['timestamp']).equals('2025-03-12T10:00:00.000Z');
      check(json['authorized']).equals(true);
      check(json['client_id']).equals('client-1');
      check(json['operation']).equals('read');
      check(json['resource']).equals('dbo.users');
      check(json.containsKey('reason')).isFalse();
    });

    test('toJson should omit null optional fields', () {
      final metric = AuthorizationMetric(
        timestamp: DateTime.utc(2025, 3, 12),
        authorized: false,
      );

      final json = metric.toJson();

      check(json['authorized']).equals(false);
      check(json.containsKey('client_id')).isFalse();
      check(json.containsKey('operation')).isFalse();
      check(json.containsKey('resource')).isFalse();
      check(json.containsKey('reason')).isFalse();
    });
  });

  group('AuthorizationMetricsSummary', () {
    test('fromList should count authorized and denied', () {
      final metrics = [
        AuthorizationMetric(
          timestamp: DateTime.now(),
          authorized: true,
        ),
        AuthorizationMetric(
          timestamp: DateTime.now(),
          authorized: true,
        ),
        AuthorizationMetric(
          timestamp: DateTime.now(),
          authorized: false,
          operation: 'read',
          resource: 'dbo.users',
          reason: 'missing_permission',
        ),
      ];

      final summary = AuthorizationMetricsSummary.fromList(metrics);

      check(summary.totalAuthorized).equals(2);
      check(summary.totalDenied).equals(1);
      check(summary.total).equals(3);
      check(summary.denialRate).isCloseTo(1 / 3, 0.001);
    });

    test('fromList should aggregate deniedByOperation', () {
      final metrics = [
        AuthorizationMetric(
          timestamp: DateTime.now(),
          authorized: false,
          operation: 'read',
        ),
        AuthorizationMetric(
          timestamp: DateTime.now(),
          authorized: false,
          operation: 'read',
        ),
        AuthorizationMetric(
          timestamp: DateTime.now(),
          authorized: false,
          operation: 'delete',
        ),
      ];

      final summary = AuthorizationMetricsSummary.fromList(metrics);

      check(summary.deniedByOperation['read']).equals(2);
      check(summary.deniedByOperation['delete']).equals(1);
    });

    test('fromList should calculate p95 and p99 latency by method', () {
      final metrics = [
        for (final latency in [10, 20, 30, 40, 50, 60, 70, 80, 90, 100])
          AuthorizationMetric(
            timestamp: DateTime.now(),
            authorized: true,
            method: 'sql.execute',
            latencyMs: latency,
          ),
      ];

      final summary = AuthorizationMetricsSummary.fromList(metrics);

      check(summary.p95LatencyByMethodMs['sql.execute']).equals(100);
      check(summary.p99LatencyByMethodMs['sql.execute']).equals(100);
      check(summary.overallP95LatencyMs).equals(100);
      check(summary.overallP99LatencyMs).equals(100);
    });

    test('denialRate should be 0 when total is 0', () {
      final summary = AuthorizationMetricsSummary.fromList([]);

      check(summary.total).equals(0);
      check(summary.denialRate).equals(0);
    });
  });

  group('AuthorizationMetricsCollector', () {
    late AuthorizationMetricsCollector collector;

    setUp(() {
      collector = AuthorizationMetricsCollector();
    });

    test('recordAuthorized should add metric', () {
      collector.recordAuthorized(
        clientId: 'client-1',
        operation: 'read',
        resource: 'dbo.users',
      );

      check(collector.metrics.length).equals(1);
      check(collector.metrics.first.authorized).isTrue();
      check(collector.metrics.first.clientId).equals('client-1');
      check(collector.metrics.first.operation).equals('read');
      check(collector.metrics.first.resource).equals('dbo.users');
    });

    test('recordDenied should add metric', () {
      collector.recordDenied(
        requestId: 'req-1',
        method: 'sql.execute',
        latencyMs: 25,
        clientId: 'client-1',
        operation: 'read',
        resource: 'dbo.other',
        reason: 'missing_permission',
      );

      check(collector.metrics.length).equals(1);
      check(collector.metrics.first.authorized).isFalse();
      check(collector.metrics.first.reason).equals('missing_permission');
      check(collector.metrics.first.requestId).equals('req-1');
      check(collector.metrics.first.method).equals('sql.execute');
      check(collector.metrics.first.latencyMs).equals(25);
    });

    test('getSummary should return correct counts', () {
      collector.recordAuthorized(clientId: 'c1');
      collector.recordAuthorized(clientId: 'c2');
      collector.recordDenied(
        clientId: 'c1',
        operation: 'delete',
        resource: 'dbo.users',
        reason: 'missing_permission',
      );

      final summary = collector.getSummary();

      check(summary.totalAuthorized).equals(2);
      check(summary.totalDenied).equals(1);
      check(summary.deniedByOperation['delete']).equals(1);
      check(summary.deniedByResource['dbo.users']).equals(1);
      check(summary.deniedByReason['missing_permission']).equals(1);
    });

    test('getSummary with period should filter by timestamp', () {
      collector.recordAuthorized(clientId: 'c1');
      collector.recordAuthorized(clientId: 'c2');

      final fullSummary = collector.getSummary();
      check(fullSummary.totalAuthorized).equals(2);

      final emptySummary = collector.getSummary(period: Duration.zero);
      check(emptySummary.totalAuthorized).equals(0);
      check(emptySummary.total).equals(0);
    });

    test('clear should remove all metrics', () {
      collector.recordAuthorized(clientId: 'c1');
      collector.recordDenied(clientId: 'c1', reason: 'revoked');

      collector.clear();

      check(collector.metrics).isEmpty();
      check(collector.getSummary().total).equals(0);
    });

    test('metrics list should be unmodifiable', () {
      collector.recordAuthorized(clientId: 'c1');

      check(
        () => collector.metrics.add(
          AuthorizationMetric(
            timestamp: DateTime.now(),
            authorized: false,
          ),
        ),
      ).throws<UnsupportedError>();
    });
  });
}
