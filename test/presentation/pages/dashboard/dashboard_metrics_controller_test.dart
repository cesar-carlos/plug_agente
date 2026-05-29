import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/query_metrics.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';
import 'package:plug_agente/presentation/pages/dashboard/dashboard_metrics_controller.dart';

class _FakeMetricsCollector implements IMetricsCollector {
  _FakeMetricsCollector(this._metrics);

  List<QueryMetrics> _metrics;
  final StreamController<QueryMetrics> _controller = StreamController<QueryMetrics>.broadcast();

  @override
  List<QueryMetrics> get metrics => _metrics;

  @override
  Stream<QueryMetrics> get metricsStream => _controller.stream;

  @override
  MetricsSummary getSummary({int limit = 100}) => MetricsSummary.fromList(_metrics);

  @override
  Map<String, Object> getSnapshot() => <String, Object>{};

  void emit(QueryMetrics metric) {
    _metrics = <QueryMetrics>[..._metrics, metric];
    _controller.add(metric);
  }

  Future<void> close() => _controller.close();
}

QueryMetrics _metricAt(DateTime timestamp) {
  return QueryMetrics(
    queryId: 'q-${timestamp.microsecondsSinceEpoch}',
    query: 'SELECT 1',
    executionDuration: const Duration(milliseconds: 10),
    rowsAffected: 1,
    columnCount: 1,
    timestamp: timestamp,
    success: true,
  );
}

void main() {
  group('DashboardMetricsController', () {
    final fixedNow = DateTime(2026, 5, 29, 12);

    late _FakeMetricsCollector collector;

    DashboardMetricsController build({
      List<QueryMetrics> metrics = const <QueryMetrics>[],
      IAppSettingsStore? store,
    }) {
      collector = _FakeMetricsCollector(List<QueryMetrics>.from(metrics));
      final controller = DashboardMetricsController(
        metricsCollector: collector,
        refreshInterval: const Duration(hours: 1),
        settingsStore: store,
        now: () => fixedNow,
      );
      addTearDown(controller.dispose);
      addTearDown(collector.close);
      return controller;
    }

    test('should default to the all period and summarize every metric', () {
      final controller = build(
        metrics: [_metricAt(fixedNow), _metricAt(fixedNow.subtract(const Duration(days: 2)))],
      )..initialize();

      expect(controller.selectedPeriod, DashboardMetricsPeriod.all);
      expect(controller.summary.totalQueries, 2);
    });

    test('should restore the persisted period on initialize', () {
      final store = InMemoryAppSettingsStore(<String, Object>{
        'dashboard_metrics_period': '1h',
      });
      final controller = build(store: store)..initialize();

      expect(controller.selectedPeriod, DashboardMetricsPeriod.last1h);
    });

    test('should exclude metrics older than the selected window', () async {
      final controller = build(
        metrics: [
          _metricAt(fixedNow.subtract(const Duration(minutes: 30))),
          _metricAt(fixedNow.subtract(const Duration(hours: 5))),
        ],
      )..initialize();

      expect(controller.summary.totalQueries, 2, reason: 'all period counts everything');

      await controller.changePeriod(DashboardMetricsPeriod.last1h);

      expect(controller.summary.totalQueries, 1, reason: 'only the 30-min-old metric is within 1h');
    });

    test('should persist the period and notify listeners on change', () async {
      final store = InMemoryAppSettingsStore();
      var notifications = 0;
      final controller = build(store: store)..initialize();
      controller.addListener(() => notifications++);

      await controller.changePeriod(DashboardMetricsPeriod.last24h);

      expect(controller.selectedPeriod, DashboardMetricsPeriod.last24h);
      expect(store.getString('dashboard_metrics_period'), '24h');
      expect(notifications, greaterThan(0));
    });

    test('should recompute when the collector emits a metric', () async {
      final controller = build()..initialize();
      expect(controller.summary.totalQueries, 0);

      var notified = false;
      controller.addListener(() => notified = true);
      collector.emit(_metricAt(fixedNow));
      await Future<void>.delayed(Duration.zero);

      expect(notified, isTrue);
      expect(controller.summary.totalQueries, 1);
    });
  });
}
