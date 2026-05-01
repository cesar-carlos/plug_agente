import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/authorization_metrics_summary.dart';
import 'package:plug_agente/domain/entities/sql_investigation_event.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/sql_investigation_provider.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/navigation/app_fluent_tab_view.dart';
import 'package:provider/provider.dart';

class WebSocketLogViewer extends StatelessWidget {
  const WebSocketLogViewer({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<WebSocketLogProvider>(
      builder: (context, logProvider, child) {
        return AppCard(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final spacing = constraints.maxHeight < 50 ? AppSpacing.sm : AppSpacing.md;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.wsLogTitle, style: context.sectionTitle),
                  SizedBox(height: spacing),
                  Expanded(
                    child: _WebSocketLogTabbedPane(
                      l10n: l10n,
                      logProvider: logProvider,
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
}

class _DeprecationSummaryCard extends StatelessWidget {
  const _DeprecationSummaryCard({
    required this.l10n,
    required this.count,
  });

  final AppLocalizations l10n;
  final int count;

  @override
  Widget build(BuildContext context) {
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
  const _AuthorizationSummaryCard({
    required this.l10n,
    required this.summary,
  });

  final AppLocalizations l10n;
  final AuthorizationMetricsSummary? summary;

  @override
  Widget build(BuildContext context) {
    if (summary == null) {
      return const SizedBox.shrink();
    }

    final colors = context.appColors;
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
            valueColor: colors.success,
          ),
          _SummaryChip(
            label: l10n.wsLogDenied,
            value: summary!.totalDenied.toString(),
            valueColor: summary!.totalDenied > 0 ? colors.error : null,
          ),
          _SummaryChip(
            label: l10n.wsLogDenialRate,
            value: '$denialRate%',
            valueColor: summary!.totalDenied > 0 ? colors.error : null,
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

class _WebSocketLogTabbedPane extends StatefulWidget {
  const _WebSocketLogTabbedPane({
    required this.l10n,
    required this.logProvider,
  });

  final AppLocalizations l10n;
  final WebSocketLogProvider logProvider;

  @override
  State<_WebSocketLogTabbedPane> createState() => _WebSocketLogTabbedPaneState();
}

class _WebSocketLogTabbedPaneState extends State<_WebSocketLogTabbedPane> {
  int _tabIndex = 0;
  StreamSubscription<void>? _authMetricsSub;
  StreamSubscription<void>? _deprecationMetricsSub;
  AuthorizationMetricsSummary? _authSummary;
  int? _deprecationCount;

  void _snapMetrics() {
    _authSummary = getIt.isRegistered<IAuthorizationMetricsCollector>()
        ? getIt<IAuthorizationMetricsCollector>().getSummary()
        : null;
    _deprecationCount = getIt.isRegistered<IDeprecationMetricsCollector>()
        ? getIt<IDeprecationMetricsCollector>().preserveSqlUsageCount
        : null;
  }

  @override
  void initState() {
    super.initState();
    _snapMetrics();
    if (getIt.isRegistered<IAuthorizationMetricsCollector>()) {
      _authMetricsSub = getIt<IAuthorizationMetricsCollector>().updates.listen((_) {
        if (mounted) {
          setState(_snapMetrics);
        }
      });
    }
    if (getIt.isRegistered<IDeprecationMetricsCollector>()) {
      _deprecationMetricsSub = getIt<IDeprecationMetricsCollector>().updates.listen((_) {
        if (mounted) {
          setState(_snapMetrics);
        }
      });
    }
  }

  @override
  void dispose() {
    _authMetricsSub?.cancel();
    _deprecationMetricsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showSqlTab = getIt<FeatureFlags>().enableDashboardSqlInvestigationFeed;
    if (!showSqlTab && _tabIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _tabIndex = 0);
        }
      });
    }
    return Consumer<SqlInvestigationProvider>(
      builder: (BuildContext context, SqlInvestigationProvider sqlProvider, Widget? _) {
        final items = <AppFluentTabItem>[
          AppFluentTabItem(
            icon: FluentIcons.plug_connected,
            text: widget.l10n.wsLogTabStream,
            body: _buildMessageList(context),
          ),
          if (showSqlTab)
            AppFluentTabItem(
              icon: FluentIcons.database,
              text: widget.l10n.wsLogTabSqlInvestigation,
              body: _buildSqlInvestigationBody(context, sqlProvider),
            ),
        ];
        return AppFluentTabView(
          currentIndex: _tabIndex.clamp(0, items.length - 1),
          onChanged: (int index) {
            if (index == _tabIndex) {
              return;
            }
            setState(() => _tabIndex = index);
          },
          items: items,
        );
      },
    );
  }

  Widget _buildMessageList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: widget.l10n.wsLogToggleEnabledTooltip,
                child: ToggleSwitch(
                  checked: widget.logProvider.isEnabled,
                  onChanged: widget.logProvider.setEnabled,
                  content: Text(widget.l10n.wsLogEnabled),
                ),
              ),
              const SizedBox(width: 16),
              Tooltip(
                message: widget.l10n.wsLogClearTooltip,
                child: AppButton(
                  label: widget.l10n.wsLogClear,
                  isPrimary: false,
                  labelStyle: context.bodyText,
                  onPressed: widget.logProvider.clearMessages,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AuthorizationSummaryCard(l10n: widget.l10n, summary: _authSummary),
              if (_deprecationCount != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _DeprecationSummaryCard(
                  l10n: widget.l10n,
                  count: _deprecationCount!,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: widget.logProvider.messages.isEmpty
              ? Center(
                  child: Text(
                    widget.l10n.wsLogNoMessages,
                    style: context.bodyMuted,
                  ),
                )
              : ListView.builder(
                  itemCount: widget.logProvider.messages.length,
                  itemBuilder: (BuildContext context, int index) {
                    final message = widget.logProvider.messages[index];
                    return _MessageItem(message: message);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSqlInvestigationBody(
    BuildContext context,
    SqlInvestigationProvider sqlProvider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Tooltip(
            message: widget.l10n.wsSqlInvestigationClearTooltip,
            child: AppButton(
              label: widget.l10n.wsSqlInvestigationClear,
              isPrimary: false,
              labelStyle: context.bodyText,
              onPressed: sqlProvider.clearEvents,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: sqlProvider.events.isEmpty
              ? Center(
                  child: Text(
                    widget.l10n.wsSqlInvestigationEmpty,
                    style: context.bodyMuted,
                  ),
                )
              : ListView.builder(
                  itemCount: sqlProvider.events.length,
                  itemBuilder: (BuildContext context, int index) {
                    return _SqlInvestigationItem(
                      event: sqlProvider.events[index],
                      l10n: widget.l10n,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

const int _kCollapsedSqlChars = 480;

class _CollapsibleSqlBlock extends StatefulWidget {
  const _CollapsibleSqlBlock({
    required this.text,
    required this.l10n,
    this.color,
  });

  final String text;
  final AppLocalizations l10n;
  final Color? color;

  @override
  State<_CollapsibleSqlBlock> createState() => _CollapsibleSqlBlockState();
}

class _CollapsibleSqlBlockState extends State<_CollapsibleSqlBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final needTruncate = text.length > _kCollapsedSqlChars;
    final display = !_expanded && needTruncate ? '${text.substring(0, _kCollapsedSqlChars)}\n…' : text;
    final baseStyle = context.bodyMuted.copyWith(
      fontFamily: 'Consolas',
      fontSize: 11,
      color: widget.color,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                display,
                style: baseStyle,
              ),
            ),
            Tooltip(
              message: widget.l10n.wsSqlInvestigationCopyTooltip,
              child: IconButton(
                icon: const Icon(FluentIcons.copy, size: 16),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                },
              ),
            ),
          ],
        ),
        if (needTruncate)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: HyperlinkButton(
              child: Text(
                _expanded ? widget.l10n.wsSqlInvestigationShowLess : widget.l10n.wsSqlInvestigationShowMore,
              ),
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
          ),
      ],
    );
  }
}

class _SqlInvestigationItem extends StatelessWidget {
  const _SqlInvestigationItem({
    required this.event,
    required this.l10n,
  });

  final SqlInvestigationEvent event;
  final AppLocalizations l10n;

  String _kindLabel() {
    return switch (event.kind) {
      SqlInvestigationKind.authorizationDenied => l10n.wsSqlInvestigationKindAuth,
      SqlInvestigationKind.executionError => l10n.wsSqlInvestigationKindExec,
    };
  }

  String _timeString() {
    final t = event.timestamp;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final colors = context.appColors;
    final isAuth = event.kind == SqlInvestigationKind.authorizationDenied;
    final chipColor = isAuth ? colors.warning : colors.error;

    return Semantics(
      container: true,
      label: '${_kindLabel()}, ${event.method}',
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md - 4),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: chipColor.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                Tooltip(
                  message: _kindLabel(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: chipColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      _kindLabel(),
                      style: context.bodyMuted.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: chipColor,
                      ),
                    ),
                  ),
                ),
                Text(
                  '[${_timeString()}] ${event.method}',
                  style: context.bodyMuted.copyWith(fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (event.reason != null && event.reason!.isNotEmpty) ...[
              _MetaRow(label: l10n.wsSqlInvestigationReason, value: event.reason!),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (event.rpcRequestId != null && event.rpcRequestId!.isNotEmpty) ...[
              _MetaRow(label: l10n.wsSqlInvestigationRpcId, value: event.rpcRequestId!),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (event.internalQueryId != null && event.internalQueryId!.isNotEmpty) ...[
              _MetaRow(label: l10n.wsSqlInvestigationInternalId, value: event.internalQueryId!),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (event.clientId != null && event.clientId!.isNotEmpty) ...[
              _MetaRow(label: l10n.wsSqlInvestigationMetaClientId, value: event.clientId!),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (event.resource != null && event.resource!.isNotEmpty) ...[
              _MetaRow(label: l10n.wsSqlInvestigationMetaResource, value: event.resource!),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (event.operation != null && event.operation!.isNotEmpty) ...[
              _MetaRow(label: l10n.wsSqlInvestigationMetaOperation, value: event.operation!),
              const SizedBox(height: AppSpacing.xs),
            ],
            _MetaRow(
              label: l10n.wsSqlInvestigationExecution,
              value: event.executedInDb ? l10n.wsSqlInvestigationExecutedInDb : l10n.wsSqlInvestigationNotExecuted,
            ),
            if (event.errorMessage != null && event.errorMessage!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.wsSqlInvestigationError,
                style: context.bodyMuted.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              _CollapsibleSqlBlock(
                text: event.errorMessage!,
                l10n: l10n,
                color: colors.error,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.wsSqlInvestigationOriginalSql,
              style: context.bodyMuted.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            _CollapsibleSqlBlock(
              text: event.originalSql,
              l10n: l10n,
            ),
            if (event.effectiveSql != null && event.effectiveSql!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.wsSqlInvestigationEffectiveSql,
                style: context.bodyMuted.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              _CollapsibleSqlBlock(
                text: event.effectiveSql!,
                l10n: l10n,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(
        style: context.bodyMuted.copyWith(fontSize: 11),
        children: <InlineSpan>[
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: value,
            style: context.bodyText.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _MessageItem extends StatelessWidget {
  const _MessageItem({required this.message});

  final WebSocketMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final color = _resolveColor(context, message.direction);

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

  Color _resolveColor(BuildContext context, String direction) {
    final colors = context.appColors;
    if (direction == 'SENT') {
      return colors.brand;
    }
    if (direction == 'AUTH') {
      return colors.warning;
    }
    if (direction == 'ERROR') {
      return colors.error;
    }

    return colors.textPrimary;
  }
}
