import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/query_metrics.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:plug_agente/presentation/widgets/connection_status_widget.dart';
import 'package:plug_agente/presentation/widgets/websocket_log_viewer.dart';
import 'package:provider/provider.dart';

enum _MetricsPeriod { last1h, last24h, all }

const _dashboardMetricsPeriodKey = 'dashboard_metrics_period';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  MetricsSummary _metricsSummary = MetricsSummary.fromList([]);
  _MetricsPeriod _selectedPeriod = _MetricsPeriod.all;
  Timer? _metricsTimer;
  StreamSubscription<QueryMetrics>? _metricsSubscription;

  @override
  void initState() {
    super.initState();
    _setupWebSocketLogging();
    _updateMetrics();
    unawaited(
      _restoreMetricsPeriod().catchError(
        (Object e) => AppLogger.warning('Failed to restore metrics period', e),
      ),
    );
    _metricsTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _updateMetrics(),
    );
    _metricsSubscription = getIt<IMetricsCollector>().metricsStream.listen(
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
      } on Object catch (error, stackTrace) {
        AppLogger.warning(
          'Transport client not available for WebSocket logging yet',
          error,
          stackTrace,
        );
      }
    });
  }

  void _updateMetrics() {
    if (!mounted) return;
    final summary = _buildSummaryForPeriod(
      getIt<IMetricsCollector>().metrics,
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
    final prefs = getIt<IAppSettingsStore>();
    final storedValue = prefs.getString(_dashboardMetricsPeriodKey);
    final restored = _metricsPeriodFromStorage(storedValue);
    if (!mounted) {
      return;
    }

    setState(() => _selectedPeriod = restored);
    _updateMetrics();
  }

  Future<void> _saveMetricsPeriod(_MetricsPeriod period) async {
    final prefs = getIt<IAppSettingsStore>();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(title: Text(AppStrings.navDashboard)),
      content: Padding(
        padding: AppLayout.pagePadding(context),
        child: AppLayout.centeredContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppConstants.appName,
                style: context.pageTitle,
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.dashboardDescription,
                style: context.bodyMuted,
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
                  unawaited(
                    _saveMetricsPeriod(period).catchError(
                      (Object e) => AppLogger.warning(
                        'Failed to save metrics period',
                        e,
                      ),
                    ),
                  );
                  _updateMetrics();
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              const Expanded(child: WebSocketLogViewer()),
            ],
          ),
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
                    style: context.sectionTitle,
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
                  valueColor: summary.failedQueries > 0
                      ? AppColors.error
                      : null,
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
            style: context.bodyMuted,
          ),
          Text(
            value,
            style: context.metricValue.copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}
