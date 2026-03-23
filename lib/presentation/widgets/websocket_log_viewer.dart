import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/authorization_metrics_summary.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:provider/provider.dart';

class WebSocketLogViewer extends StatelessWidget {
  const WebSocketLogViewer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketLogProvider>(
      builder: (context, logProvider, child) {
        final l10n = AppLocalizations.of(context)!;
        final authSummary = _getAuthSummary();
        final deprecationCount = _getPreserveSqlDeprecatedCount();

        return AppCard(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final spacing = constraints.maxHeight < 50 ? AppSpacing.sm : AppSpacing.md;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.wsLogTitle, style: context.sectionTitle),
                      Row(
                        children: [
                          ToggleSwitch(
                            checked: logProvider.isEnabled,
                            onChanged: logProvider.setEnabled,
                            content: Text(l10n.wsLogEnabled),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Button(
                            onPressed: logProvider.clearMessages,
                            child: Text(
                              l10n.wsLogClear,
                              style: context.bodyText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: spacing),
                  _AuthorizationSummaryCard(summary: authSummary),
                  if (deprecationCount != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _DeprecationSummaryCard(count: deprecationCount),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(
                    child: logProvider.messages.isEmpty
                        ? Center(
                            child: Text(
                              l10n.wsLogNoMessages,
                              style: context.bodyMuted,
                            ),
                          )
                        : ListView.builder(
                            itemCount: logProvider.messages.length,
                            itemBuilder: (context, index) {
                              final message = logProvider.messages[index];
                              return _MessageItem(message: message);
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  AuthorizationMetricsSummary? _getAuthSummary() {
    if (!getIt.isRegistered<IAuthorizationMetricsCollector>()) {
      return null;
    }

    final collector = getIt<IAuthorizationMetricsCollector>();
    return collector.getSummary();
  }

  int? _getPreserveSqlDeprecatedCount() {
    if (!getIt.isRegistered<IDeprecationMetricsCollector>()) {
      return null;
    }
    return getIt<IDeprecationMetricsCollector>().preserveSqlUsageCount;
  }
}

class _DeprecationSummaryCard extends StatelessWidget {
  const _DeprecationSummaryCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
      ),
      child: Row(
        children: [
          Text(
            l10n.wsLogPreserveSqlDeprecatedUses,
            style: context.bodyMuted,
          ),
          Text(
            ': $count',
            style: context.bodyText.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _AuthorizationSummaryCard extends StatelessWidget {
  const _AuthorizationSummaryCard({required this.summary});

  final AuthorizationMetricsSummary? summary;

  @override
  Widget build(BuildContext context) {
    if (summary == null) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;
    final denialRate = (summary!.denialRate * 100).toStringAsFixed(1);
    final missingPermissionRate = (summary!.reasonRate('missing_permission') * 100).toStringAsFixed(1);
    final tokenNotFoundRate = (summary!.reasonRate('token_not_found') * 100).toStringAsFixed(1);
    final tokenRevokedRate = (summary!.reasonRate('token_revoked') * 100).toStringAsFixed(1);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: [
          _SummaryChip(
            label: l10n.wsLogAuthChecks,
            value: summary!.total.toString(),
          ),
          _SummaryChip(
            label: l10n.wsLogAllowed,
            value: summary!.totalAuthorized.toString(),
            valueColor: Colors.green,
          ),
          _SummaryChip(
            label: l10n.wsLogDenied,
            value: summary!.totalDenied.toString(),
            valueColor: summary!.totalDenied > 0 ? Colors.red : null,
          ),
          _SummaryChip(
            label: l10n.wsLogDenialRate,
            value: '$denialRate%',
            valueColor: summary!.totalDenied > 0 ? Colors.red : null,
          ),
          _SummaryChip(
            label: l10n.wsLogP95Latency,
            value: _formatLatency(summary!.overallP95LatencyMs),
          ),
          _SummaryChip(
            label: l10n.wsLogP99Latency,
            value: _formatLatency(summary!.overallP99LatencyMs),
          ),
          _SummaryChip(
            label: 'missing_permission',
            value: '$missingPermissionRate%',
          ),
          _SummaryChip(
            label: 'token_not_found',
            value: '$tokenNotFoundRate%',
          ),
          _SummaryChip(
            label: 'token_revoked',
            value: '$tokenRevokedRate%',
          ),
        ],
      ),
    );
  }

  String _formatLatency(int latencyMs) {
    if (latencyMs <= 0) {
      return 'n/a';
    }
    return '${latencyMs}ms';
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: context.bodyMuted),
        Text(
          value,
          style: context.bodyText.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _MessageItem extends StatelessWidget {
  const _MessageItem({required this.message});

  final WebSocketMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final color = _resolveColor(theme, message.direction);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md - 4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  message.direction,
                  style: context.bodyMuted.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message.event,
                  style: context.bodyText.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            message.formattedData,
            style: context.bodyMuted.copyWith(
              fontFamily: 'Consolas',
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Color _resolveColor(FluentThemeData theme, String direction) {
    if (direction == 'SENT') {
      return theme.accentColor;
    }
    if (direction == 'AUTH') {
      return Colors.orange;
    }
    if (direction == 'ERROR') {
      return Colors.red;
    }

    return theme.brightness == Brightness.dark ? Colors.white : Colors.black;
  }
}
