import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/query_metrics.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';

/// Time window used to summarize ODBC query metrics on the dashboard.
enum DashboardMetricsPeriod { last1h, last24h, all }

/// Owns the dashboard's metrics lifecycle: periodic refresh, live stream
/// updates, period selection and its persistence.
///
/// Extracted from `DashboardPage` so the page keeps only layout and the
/// metrics/timer/stream wiring becomes injectable and unit-testable.
class DashboardMetricsController extends ChangeNotifier {
  DashboardMetricsController({
    required IMetricsCollector metricsCollector,
    required Duration refreshInterval,
    IAppSettingsStore? settingsStore,
    DateTime Function() now = DateTime.now,
  }) : _metricsCollector = metricsCollector,
       _refreshInterval = refreshInterval,
       _settingsStore = settingsStore,
       _now = now;

  static const String _periodStorageKey = 'dashboard_metrics_period';

  final IMetricsCollector _metricsCollector;
  final Duration _refreshInterval;
  final IAppSettingsStore? _settingsStore;
  final DateTime Function() _now;

  Timer? _timer;
  StreamSubscription<QueryMetrics>? _subscription;

  MetricsSummary _summary = MetricsSummary.fromList(const <QueryMetrics>[]);
  DashboardMetricsPeriod _selectedPeriod = DashboardMetricsPeriod.all;

  MetricsSummary get summary => _summary;
  DashboardMetricsPeriod get selectedPeriod => _selectedPeriod;

  /// Restores the persisted period, computes the first summary and starts the
  /// periodic refresh timer and the live metrics subscription.
  void initialize() {
    _restorePeriod();
    _recompute();
    _timer = Timer.periodic(_refreshInterval, (_) => _recompute());
    _subscription = _metricsCollector.metricsStream.listen(
      (_) => _recompute(),
      onError: (Object error, StackTrace stackTrace) => AppLogger.warning('Metrics stream error', error, stackTrace),
    );
  }

  Future<void> changePeriod(DashboardMetricsPeriod period) async {
    if (period == _selectedPeriod) {
      return;
    }
    _selectedPeriod = period;
    _recompute();
    await _persistPeriod(period);
  }

  void _recompute() {
    _summary = _buildSummaryForPeriod(_metricsCollector.metrics, _selectedPeriod);
    notifyListeners();
  }

  MetricsSummary _buildSummaryForPeriod(List<QueryMetrics> metrics, DashboardMetricsPeriod period) {
    if (period == DashboardMetricsPeriod.all) {
      return MetricsSummary.fromList(metrics);
    }

    final cutoff = period == DashboardMetricsPeriod.last1h
        ? _now().subtract(const Duration(hours: 1))
        : _now().subtract(const Duration(hours: 24));
    final filtered = metrics.where((metric) => metric.timestamp.isAfter(cutoff)).toList();

    return MetricsSummary.fromList(filtered);
  }

  void _restorePeriod() {
    final store = _settingsStore;
    if (store == null) {
      return;
    }
    _selectedPeriod = _periodFromStorage(store.getString(_periodStorageKey));
  }

  Future<void> _persistPeriod(DashboardMetricsPeriod period) async {
    final store = _settingsStore;
    if (store == null) {
      return;
    }
    try {
      await store.setString(_periodStorageKey, _periodToStorage(period));
    } on Object catch (error, stackTrace) {
      AppLogger.warning('Failed to save metrics period', error, stackTrace);
    }
  }

  static String _periodToStorage(DashboardMetricsPeriod period) {
    return switch (period) {
      DashboardMetricsPeriod.last1h => '1h',
      DashboardMetricsPeriod.last24h => '24h',
      DashboardMetricsPeriod.all => 'all',
    };
  }

  static DashboardMetricsPeriod _periodFromStorage(String? value) {
    return switch (value) {
      '1h' => DashboardMetricsPeriod.last1h,
      '24h' => DashboardMetricsPeriod.last24h,
      _ => DashboardMetricsPeriod.all,
    };
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
