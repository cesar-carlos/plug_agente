import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/entities/authorization_metrics_summary.dart';
import 'package:plug_agente/domain/entities/protocol_metrics_summary.dart';
import 'package:plug_agente/domain/entities/sql_investigation_event.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_protocol_metrics_collector.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/presentation_provider_read.dart';
import 'package:plug_agente/presentation/providers/sql_investigation_provider.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:plug_agente/presentation/widgets/websocket_log_metrics_summary_cards.dart';
import 'package:plug_agente/shared/widgets/common/actions/app_button.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/navigation/app_fluent_tab_view.dart';
import 'package:provider/provider.dart';

class WebSocketLogViewer extends StatelessWidget {
  const WebSocketLogViewer({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                child: _WebSocketLogTabbedPane(l10n: l10n),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WebSocketLogTabbedPane extends StatefulWidget {
  const _WebSocketLogTabbedPane({
    required this.l10n,
  });

  final AppLocalizations l10n;

  @override
  State<_WebSocketLogTabbedPane> createState() => _WebSocketLogTabbedPaneState();
}

class _WebSocketLogTabbedPaneState extends State<_WebSocketLogTabbedPane> {
  int _tabIndex = 0;
  var _metricsSubscriptionsInitialized = false;
  StreamSubscription<void>? _authMetricsSub;
  StreamSubscription<void>? _deprecationMetricsSub;
  StreamSubscription<void>? _protocolMetricsSub;
  Timer? _metricsDebounceTimer;
  AuthorizationMetricsSummary? _authSummary;
  int? _deprecationCount;
  ProtocolMetricsSummary? _protocolSummary;

  void _scheduleMetricsSnap() {
    _metricsDebounceTimer?.cancel();
    _metricsDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      _metricsDebounceTimer = null;
      if (!mounted) {
        return;
      }
      setState(_snapMetrics);
    });
  }

  void _snapMetrics() {
    final authMetrics = readOptionalPresentationProvider<IAuthorizationMetricsCollector>(context);
    _authSummary = authMetrics?.getSummary();
    final deprecationMetrics = readOptionalPresentationProvider<IDeprecationMetricsCollector>(context);
    _deprecationCount = deprecationMetrics?.preserveSqlUsageCount;
    final protocolMetrics = _readProtocolMetricsCollector(context);
    _protocolSummary = protocolMetrics?.getSummary(period: const Duration(minutes: 15));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_metricsSubscriptionsInitialized) {
      return;
    }
    _metricsSubscriptionsInitialized = true;
    _snapMetrics();
    final authMetrics = readOptionalPresentationProvider<IAuthorizationMetricsCollector>(context);
    if (authMetrics != null) {
      _authMetricsSub = authMetrics.updates.listen((_) {
        if (mounted) {
          _scheduleMetricsSnap();
        }
      });
    }
    final deprecationMetrics = readOptionalPresentationProvider<IDeprecationMetricsCollector>(context);
    if (deprecationMetrics != null) {
      _deprecationMetricsSub = deprecationMetrics.updates.listen((_) {
        if (mounted) {
          _scheduleMetricsSnap();
        }
      });
    }
    final protocolMetrics = _readProtocolMetricsCollector(context);
    if (protocolMetrics != null) {
      _protocolMetricsSub = protocolMetrics.updates.listen((_) {
        if (mounted) {
          _scheduleMetricsSnap();
        }
      });
    }
  }

  IProtocolMetricsCollector? _readProtocolMetricsCollector(BuildContext context) {
    try {
      return context.read<IProtocolMetricsCollector>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void dispose() {
    _metricsDebounceTimer?.cancel();
    _authMetricsSub?.cancel();
    _deprecationMetricsSub?.cancel();
    _protocolMetricsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showSqlTab = context.read<FeatureFlags>().enableDashboardSqlInvestigationFeed;
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
            body: _WebSocketMessageListPane(
              l10n: widget.l10n,
              authSummary: _authSummary,
              protocolSummary: _protocolSummary,
              deprecationCount: _deprecationCount,
            ),
          ),
          if (showSqlTab)
            AppFluentTabItem(
              icon: FluentIcons.database,
              text: widget.l10n.wsLogTabSqlInvestigation,
              body: _SqlInvestigationPane(
                l10n: widget.l10n,
                sqlProvider: sqlProvider,
              ),
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
}

/// Stream tab body: enable/clear controls, metric summary cards and the
/// scrollable message list. Rebuilds with its parent so live metric and log
/// updates stay visible.
class _WebSocketMessageListPane extends StatelessWidget {
  const _WebSocketMessageListPane({
    required this.l10n,
    required this.authSummary,
    required this.protocolSummary,
    required this.deprecationCount,
  });

  final AppLocalizations l10n;
  final AuthorizationMetricsSummary? authSummary;
  final ProtocolMetricsSummary? protocolSummary;
  final int? deprecationCount;

  @override
  Widget build(BuildContext context) {
    final protocol = protocolSummary;
    final deprecations = deprecationCount;
    final logProvider = context.read<WebSocketLogProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Selector<WebSocketLogProvider, bool>(
                selector: (_, WebSocketLogProvider provider) => provider.isEnabled,
                builder: (BuildContext context, bool isEnabled, Widget? child) {
                  return Tooltip(
                    message: l10n.wsLogToggleEnabledTooltip,
                    child: ToggleSwitch(
                      checked: isEnabled,
                      onChanged: logProvider.setEnabled,
                      content: Text(l10n.wsLogEnabled),
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
              Tooltip(
                message: l10n.wsLogClearTooltip,
                child: AppButton(
                  label: l10n.wsLogClear,
                  isPrimary: false,
                  labelStyle: context.bodyText,
                  onPressed: logProvider.clearMessages,
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
              WebSocketLogAuthorizationSummaryCard(l10n: l10n, summary: authSummary),
              if (protocol != null && protocol.totalMessages > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                WebSocketLogProtocolMetricsSummaryCard(summary: protocol),
              ],
              if (deprecations != null) ...[
                const SizedBox(height: AppSpacing.sm),
                WebSocketLogDeprecationSummaryCard(
                  l10n: l10n,
                  count: deprecations,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: ListenableBuilder(
            listenable: logProvider,
            builder: (BuildContext context, Widget? child) {
              final messages = logProvider.messages;
              if (messages.isEmpty) {
                return Center(
                  child: Text(
                    l10n.wsLogNoMessages,
                    style: context.bodyMuted,
                  ),
                );
              }
              final visibleCount = messages.length.clamp(
                0,
                AppConstants.dashboardDiagnosticFeedMaxVisibleItems,
              );
              return ListView.builder(
                itemCount: visibleCount,
                itemBuilder: (BuildContext context, int index) {
                  return RepaintBoundary(
                    child: _MessageItem(message: messages[index]),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// SQL investigation tab body: clear control and the scrollable event list.
class _SqlInvestigationPane extends StatelessWidget {
  const _SqlInvestigationPane({
    required this.l10n,
    required this.sqlProvider,
  });

  final AppLocalizations l10n;
  final SqlInvestigationProvider sqlProvider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Tooltip(
            message: l10n.wsSqlInvestigationClearTooltip,
            child: AppButton(
              label: l10n.wsSqlInvestigationClear,
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
                    l10n.wsSqlInvestigationEmpty,
                    style: context.bodyMuted,
                  ),
                )
              : ListView.builder(
                  itemCount: sqlProvider.events.length,
                  itemBuilder: (BuildContext context, int index) {
                    return _SqlInvestigationItem(
                      event: sqlProvider.events[index],
                      l10n: l10n,
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
          Text(
            message.formattedData,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
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
    if (direction == 'SECURITY') {
      return colors.warning;
    }
    if (direction == 'PERFORMANCE') {
      return colors.warning;
    }
    if (direction == 'ERROR') {
      return colors.error;
    }

    return colors.textPrimary;
  }
}
