import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/services/query_processing_service.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/theme/app_colors.dart';
import 'package:plug_agente/core/theme/app_spacing.dart';
import 'package:plug_agente/domain/entities/query_metrics.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:plug_agente/presentation/widgets/connection_status_widget.dart';
import 'package:plug_agente/presentation/widgets/websocket_log_viewer.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _MetricsPeriod { last1h, last24h, all }

const _dashboardMetricsPeriodKey = 'dashboard_metrics_period';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final QueryProcessingService _queryProcessingService;
  MetricsSummary _metricsSummary = MetricsSummary.fromList([]);
  _MetricsPeriod _selectedPeriod = _MetricsPeriod.all;
  Timer? _metricsTimer;
  StreamSubscription<QueryMetrics>? _metricsSubscription;

  @override
  void initState() {
    super.initState();
    _queryProcessingService = getIt<QueryProcessingService>();
    _queryProcessingService.start();
    _setupWebSocketLogging();
    _updateMetrics();
    unawaited(_restoreMetricsPeriod());
    _metricsTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _updateMetrics(),
    );
    _metricsSubscription = MetricsCollector.instance.metricsStream.listen(
      (_) => _updateMetrics(),
    );
  }

  void _setupWebSocketLogging() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final logProvider = Provider.of<WebSocketLogProvider>(
        context,
        listen: false,
      );
      try {
        final transportClient = getIt<ITransportClient>();
        transportClient.setMessageCallback(logProvider.addMessage);
      } on Exception {
        // Transport client might not be initialized yet
      }
    });
  }

  void _updateMetrics() {
    if (!mounted) return;
    final summary = _buildSummaryForPeriod(
      MetricsCollector.instance.metrics,
      _selectedPeriod,
    );
    setState(() => _metricsSummary = summary);
  }

  MetricsSummary _buildSummaryForPeriod(
    List<QueryMetrics> metrics,
    _MetricsPeriod period,
  ) {
    if (period == _MetricsPeriod.all) {
      return MetricsSummary.fromList(metrics);
    }

    final now = DateTime.now();
    final cutoff = period == _MetricsPeriod.last1h
        ? now.subtract(const Duration(hours: 1))
        : now.subtract(const Duration(hours: 24));

    final filtered = metrics
        .where((metric) => metric.timestamp.isAfter(cutoff))
        .toList();

    return MetricsSummary.fromList(filtered);
  }

  Future<void> _restoreMetricsPeriod() async {
    final prefs = getIt<SharedPreferences>();
    final storedValue = prefs.getString(_dashboardMetricsPeriodKey);
    final restored = _metricsPeriodFromStorage(storedValue);
    if (!mounted) {
      return;
    }

    setState(() => _selectedPeriod = restored);
    _updateMetrics();
  }

  Future<void> _saveMetricsPeriod(_MetricsPeriod period) async {
    final prefs = getIt<SharedPreferences>();
    await prefs.setString(
      _dashboardMetricsPeriodKey,
      _metricsPeriodToStorage(period),
    );
  }

  String _metricsPeriodToStorage(_MetricsPeriod period) {
    return switch (period) {
      _MetricsPeriod.last1h => '1h',
      _MetricsPeriod.last24h => '24h',
      _MetricsPeriod.all => 'all',
    };
  }

  _MetricsPeriod _metricsPeriodFromStorage(String? value) {
    return switch (value) {
      '1h' => _MetricsPeriod.last1h,
      '24h' => _MetricsPeriod.last24h,
      _ => _MetricsPeriod.all,
    };
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    _metricsSubscription?.cancel();
    _queryProcessingService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('Dashboard')),
      content: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Plug Database',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Monitor your agent status and database connections here.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            const ConnectionStatusWidget(),
            const SizedBox(height: AppSpacing.lg),
            _OdbcMetricsCard(
              summary: _metricsSummary,
              selectedPeriod: _selectedPeriod,
              onPeriodChanged: (period) {
                if (period == null) {
                  return;
                }
                setState(() => _selectedPeriod = period);
                unawaited(_saveMetricsPeriod(period));
                _updateMetrics();
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            const Expanded(child: WebSocketLogViewer()),
          ],
        ),
      ),
    );
  }
}

class _OdbcMetricsCard extends StatelessWidget {
  const _OdbcMetricsCard({
    required this.summary,
    required this.selectedPeriod,
    required this.onPeriodChanged,
  });
  final MetricsSummary summary;
  final _MetricsPeriod selectedPeriod;
  final ValueChanged<_MetricsPeriod?> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppStrings.dashboardMetricsTitle,
                    style: theme.typography.titleLarge,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 220,
                  child: ComboBox<_MetricsPeriod>(
                    value: selectedPeriod,
                    onChanged: onPeriodChanged,
                    isExpanded: true,
                    placeholder: const Text(AppStrings.dashboardMetricsPeriod),
                    items: const [
                      ComboBoxItem(
                        value: _MetricsPeriod.last1h,
                        child: Text(AppStrings.dashboardMetricsPeriod1h),
                      ),
                      ComboBoxItem(
                        value: _MetricsPeriod.last24h,
                        child: Text(AppStrings.dashboardMetricsPeriod24h),
                      ),
                      ComboBoxItem(
                        value: _MetricsPeriod.all,
                        child: Text(AppStrings.dashboardMetricsPeriodAll),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.sm,
              children: [
                _MetricChip(
                  icon: FluentIcons.document,
                  label: AppStrings.dashboardMetricsQueries,
                  value: summary.totalQueries.toString(),
                ),
                _MetricChip(
                  icon: FluentIcons.check_mark,
                  label: AppStrings.dashboardMetricsSuccess,
                  value: summary.successfulQueries.toString(),
                  valueColor: AppColors.success,
                ),
                _MetricChip(
                  icon: FluentIcons.error_badge,
                  label: AppStrings.dashboardMetricsErrors,
                  value: summary.failedQueries.toString(),
                  valueColor:
                      summary.failedQueries > 0 ? AppColors.error : null,
                ),
                _MetricChip(
                  icon: FluentIcons.completed_solid,
                  label: AppStrings.dashboardMetricsSuccessRate,
                  value: '${summary.successRate.toStringAsFixed(1)}%',
                  valueColor: AppColors.success,
                ),
                _MetricChip(
                  icon: FluentIcons.clock,
                  label: AppStrings.dashboardMetricsAvgLatency,
                  value: _formatDuration(summary.averageExecutionTime),
                ),
                _MetricChip(
                  icon: FluentIcons.clock,
                  label: AppStrings.dashboardMetricsMaxLatency,
                  value: _formatDuration(summary.maxExecutionTime),
                ),
                _MetricChip(
                  icon: FluentIcons.table,
                  label: AppStrings.dashboardMetricsTotalRows,
                  value: summary.totalRowsAffected.toString(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inMilliseconds < 1000) {
      return '${d.inMilliseconds}ms';
    }
    return '${(d.inMilliseconds / 1000).toStringAsFixed(2)}s';
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$label: ',
            style: theme.typography.body,
          ),
          Text(
            value,
            style: theme.typography.body?.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
