import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/query_metrics.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:plug_agente/presentation/widgets/connection_status_widget.dart';
import 'package:plug_agente/presentation/widgets/websocket_log_viewer.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
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
      AppConstants.dashboardMetricsInterval,
      (_) => _updateMetrics(),
    );
    _metricsSubscription = getIt<IMetricsCollector>().metricsStream.listen(
      (_) => _updateMetrics(),
      onError: (Object e, StackTrace? s) => AppLogger.warning(
        'Metrics stream error',
        e,
        s,
      ),
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

    final filtered = metrics.where((metric) => metric.timestamp.isAfter(cutoff)).toList();

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
    final l10n = AppLocalizations.of(context)!;
    return ScaffoldPage(
      header: PageHeader(title: Text(l10n.navDashboard)),
      content: Padding(
        padding: AppLayout.pagePadding(context),
        child: AppLayout.centeredContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConstants.appName,
                      style: context.pageTitle.copyWith(
                        fontSize: 22,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.dashboardDescription,
                      style: context.bodyMuted.copyWith(
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const ConnectionStatusWidget(compact: true),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _OdbcMetricsCard(
                l10n: l10n,
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
    required this.l10n,
    required this.summary,
    required this.selectedPeriod,
    required this.onPeriodChanged,
  });
  final AppLocalizations l10n;
  final MetricsSummary summary;
  final _MetricsPeriod selectedPeriod;
  final ValueChanged<_MetricsPeriod?> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.dashboardMetricsTitle,
                  style: context.sectionTitle.copyWith(
                    fontSize: 15,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 160,
                child: ComboBox<_MetricsPeriod>(
                  value: selectedPeriod,
                  onChanged: onPeriodChanged,
                  isExpanded: true,
                  placeholder: Text(
                    l10n.dashboardMetricsPeriod,
                    style: context.bodyMuted.copyWith(fontSize: 12),
                  ),
                  items: [
                    ComboBoxItem(
                      value: _MetricsPeriod.last1h,
                      child: Text(
                        l10n.dashboardMetricsPeriod1h,
                        style: context.bodyText.copyWith(fontSize: 12),
                      ),
                    ),
                    ComboBoxItem(
                      value: _MetricsPeriod.last24h,
                      child: Text(
                        l10n.dashboardMetricsPeriod24h,
                        style: context.bodyText.copyWith(fontSize: 12),
                      ),
                    ),
                    ComboBoxItem(
                      value: _MetricsPeriod.all,
                      child: Text(
                        l10n.dashboardMetricsPeriodAll,
                        style: context.bodyText.copyWith(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _MetricChip(
                icon: FluentIcons.document,
                label: l10n.dashboardMetricsQueries,
                value: summary.totalQueries.toString(),
              ),
              _MetricChip(
                icon: FluentIcons.check_mark,
                label: l10n.dashboardMetricsSuccess,
                value: summary.successfulQueries.toString(),
                valueColor: colors.success,
              ),
              _MetricChip(
                icon: FluentIcons.error_badge,
                label: l10n.dashboardMetricsErrors,
                value: summary.failedQueries.toString(),
                valueColor: summary.failedQueries > 0 ? colors.error : null,
              ),
              _MetricChip(
                icon: FluentIcons.completed_solid,
                label: l10n.dashboardMetricsSuccessRate,
                value: '${summary.successRate.toStringAsFixed(1)}%',
                valueColor: colors.success,
              ),
              _MetricChip(
                icon: FluentIcons.clock,
                label: l10n.dashboardMetricsAvgLatency,
                value: _formatDuration(summary.averageExecutionTime),
              ),
              _MetricChip(
                icon: FluentIcons.clock,
                label: l10n.dashboardMetricsMaxLatency,
                value: _formatDuration(summary.maxExecutionTime),
              ),
              _MetricChip(
                icon: FluentIcons.table,
                label: l10n.dashboardMetricsTotalRows,
                value: summary.totalRowsAffected.toString(),
              ),
            ],
          ),
        ],
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

const EdgeInsets _metricChipPadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.sm,
  vertical: 2,
);

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
    final labelStyle = context.bodyMuted.copyWith(fontSize: 11, height: 1.1);
    final baseValueStyle = context.metricValue.copyWith(
      fontSize: 12,
      height: 1.1,
    );
    final valueStyle = valueColor != null ? baseValueStyle.copyWith(color: valueColor) : baseValueStyle;

    return Container(
      padding: _metricChipPadding,
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$label: ',
            style: labelStyle,
          ),
          Text(
            value,
            style: valueStyle,
          ),
        ],
      ),
    );
  }
}
