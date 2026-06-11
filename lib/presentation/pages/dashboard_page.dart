import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/query_metrics.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/dashboard/dashboard_metrics_controller.dart';
import 'package:plug_agente/presentation/providers/presentation_provider_read.dart';
import 'package:plug_agente/presentation/widgets/connection_status_widget.dart';
import 'package:plug_agente/presentation/widgets/websocket_log_viewer.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:provider/provider.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final DashboardMetricsController _metricsController;
  var _metricsControllerInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_metricsControllerInitialized) {
      return;
    }
    _metricsControllerInitialized = true;
    _metricsController = DashboardMetricsController(
      metricsCollector: context.read<IMetricsCollector>(),
      refreshInterval: AppConstants.dashboardMetricsInterval,
      settingsStore: readOptionalPresentationProvider<IAppSettingsStore>(context),
    )..initialize();
  }

  @override
  void dispose() {
    if (_metricsControllerInitialized) {
      _metricsController.dispose();
    }
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
              ListenableBuilder(
                listenable: _metricsController,
                builder: (context, _) => _OdbcMetricsCard(
                  l10n: l10n,
                  summary: _metricsController.summary,
                  selectedPeriod: _metricsController.selectedPeriod,
                  onPeriodChanged: (period) {
                    if (period == null) {
                      return;
                    }
                    unawaited(_metricsController.changePeriod(period));
                  },
                ),
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
  final DashboardMetricsPeriod selectedPeriod;
  final ValueChanged<DashboardMetricsPeriod?> onPeriodChanged;

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
                child: ComboBox<DashboardMetricsPeriod>(
                  value: selectedPeriod,
                  onChanged: onPeriodChanged,
                  isExpanded: true,
                  placeholder: Text(
                    l10n.dashboardMetricsPeriod,
                    style: context.bodyMuted.copyWith(fontSize: 12),
                  ),
                  items: [
                    ComboBoxItem(
                      value: DashboardMetricsPeriod.last1h,
                      child: Text(
                        l10n.dashboardMetricsPeriod1h,
                        style: context.bodyText.copyWith(fontSize: 12),
                      ),
                    ),
                    ComboBoxItem(
                      value: DashboardMetricsPeriod.last24h,
                      child: Text(
                        l10n.dashboardMetricsPeriod24h,
                        style: context.bodyText.copyWith(fontSize: 12),
                      ),
                    ),
                    ComboBoxItem(
                      value: DashboardMetricsPeriod.all,
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
