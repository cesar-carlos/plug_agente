import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/authorization_metrics_summary.dart';
import 'package:plug_agente/domain/entities/protocol_metrics_summary.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_protocol_metrics_collector.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/presentation_provider_read.dart';
import 'package:plug_agente/presentation/providers/sql_investigation_provider.dart';
import 'package:plug_agente/presentation/widgets/websocket_log/websocket_log_message_list_pane.dart';
import 'package:plug_agente/presentation/widgets/websocket_log/websocket_log_sql_investigation_pane.dart';
import 'package:plug_agente/shared/widgets/common/navigation/app_fluent_tab_view.dart';
import 'package:provider/provider.dart';

class WebSocketLogTabbedPane extends StatefulWidget {
  const WebSocketLogTabbedPane({
    required this.l10n,
    super.key,
  });

  final AppLocalizations l10n;

  @override
  State<WebSocketLogTabbedPane> createState() => _WebSocketLogTabbedPaneState();
}

class _WebSocketLogTabbedPaneState extends State<WebSocketLogTabbedPane> {
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
            body: WebSocketLogMessageListPane(
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
              body: WebSocketLogSqlInvestigationPane(
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
