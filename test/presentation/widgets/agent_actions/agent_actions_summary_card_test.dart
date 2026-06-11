import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_summary_card.dart';
import '../../pages/agent_actions/agent_actions_page_test_harness.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  AgentActionExecution buildExecution(String id, AgentActionExecutionStatus status) {
    return AgentActionExecution(
      id: id,
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: status,
      requestedAt: DateTime.utc(2026, 6, 10),
      source: AgentActionRequestSource.localUi,
    );
  }

  void seedExecutionCounts(
    AgentActionsProvider provider, {
    required int queued,
    required int running,
    required int failed,
  }) {
    provider.executionsController.executions = <AgentActionExecution>[
      for (var index = 0; index < queued; index++)
        buildExecution('queued-$index', AgentActionExecutionStatus.queued),
      for (var index = 0; index < running; index++)
        buildExecution('running-$index', AgentActionExecutionStatus.running),
      for (var index = 0; index < failed; index++)
        buildExecution('failed-$index', AgentActionExecutionStatus.failed),
    ];
    provider.executionsController.invalidateCaches();
  }

  Future<void> pumpCard(
    WidgetTester tester,
    AgentActionsProvider provider,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AgentActionsSummaryCard(provider: provider, l10n: l10n),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('should show core execution metrics from provider', (tester) async {
    final harness = AgentActionsPageHarness(useExecutionQueue: false);
    seedExecutionCounts(harness.provider, queued: 1, running: 2, failed: 3);

    await pumpCard(tester, harness.provider);

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text(l10n.agentActionsSummaryQueued), findsOneWidget);
    expect(find.text(l10n.agentActionsSummaryRunning), findsOneWidget);
    expect(find.text(l10n.agentActionsSummaryFailed), findsOneWidget);
  });

  testWidgets('should show maintenance metric when maintenance mode is on', (tester) async {
    final harness = AgentActionsPageHarness(useExecutionQueue: false);
    await harness.featureFlags.setEnableAgentActionsMaintenanceMode(true);

    await pumpCard(tester, harness.provider);

    expect(find.text(l10n.agentActionsSummaryMaintenance), findsOneWidget);
    expect(find.text(l10n.agentActionsSummaryMaintenanceActive), findsOneWidget);
  });

  testWidgets('should show com handlers count or none label when diagnostics are wired', (tester) async {
    final harnessWithoutHandlers = AgentActionsPageHarness(
      useExecutionQueue: false,
      includeComObjectRunner: true,
      comObjectInvocationDiagnostics: const FakeComObjectInvocationDiagnostics(),
    );

    await pumpCard(tester, harnessWithoutHandlers.provider);

    expect(find.text(l10n.agentActionsSummaryComHandlers), findsOneWidget);
    expect(find.text(l10n.agentActionsSummaryComHandlersNone), findsOneWidget);

    final harnessWithHandlers = AgentActionsPageHarness(
      useExecutionQueue: false,
      includeComObjectRunner: true,
      comObjectInvocationDiagnostics: const FakeComObjectInvocationDiagnostics(
        registeredHandlerCount: 4,
      ),
    );
    await pumpCard(tester, harnessWithHandlers.provider);

    expect(find.text('4'), findsOneWidget);
    expect(find.text(l10n.agentActionsSummaryComHandlersNone), findsNothing);
  });
}
