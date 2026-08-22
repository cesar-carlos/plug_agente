import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/window_constraints.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

import 'agent_actions_page_test_harness.dart';

void main() {
  late AppLocalizations ptL10n;

  setUpAll(() async {
    ptL10n = await AppLocalizations.delegate.load(const Locale('pt'));
  });

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('keeps all four tabs usable at the minimum window size', (tester) async {
    final harness = AgentActionsPageHarness();
    await tester.binding.setSurfaceSize(
      const Size(WindowConstraints.mainWindowMinWidth, WindowConstraints.mainWindowMinHeight),
    );
    await harness.pumpPage(
      tester,
      size: const Size(WindowConstraints.mainWindowMinWidth, WindowConstraints.mainWindowMinHeight),
    );

    expect(find.text(ptL10n.agentActionsSummaryActions), findsOneWidget);
    expect(find.text(ptL10n.agentActionsHistoryTitle), findsOneWidget);
    expect(find.text(ptL10n.configTabPreferences), findsOneWidget);
    expect(find.text(ptL10n.agentActionsRemoteAuditTitle), findsOneWidget);

    final tabView = tester.widget<TabView>(find.byType(TabView));
    expect(tabView.shortcutsEnabled, isFalse);
    expect(tabView.tabWidthBehavior, TabWidthBehavior.sizeToContent);
    expect(tester.takeException(), isNull);

    await openTab(tester, ptL10n.agentActionsRemoteAuditTitle);
    expect(find.text(ptL10n.agentActionsRemoteAuditDescription), findsOneWidget);
    expect(find.text(ptL10n.agentActionsRemoteAuditTitle), findsOneWidget);
  });

  testWidgets('centers history empty-selection copy instead of pinning it to the top', (tester) async {
    final harness = AgentActionsPageHarness();
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    await openTab(tester, ptL10n.agentActionsHistoryTitle);

    final emptyText = find.text(ptL10n.agentActionsEmptySelection);
    expect(emptyText, findsOneWidget);
    expect(
      find.ancestor(of: emptyText, matching: find.byType(Center)),
      findsOneWidget,
    );
  });

  testWidgets('fits the action editor dialog inside the minimum window height', (tester) async {
    final harness = AgentActionsPageHarness();
    await tester.binding.setSurfaceSize(
      const Size(WindowConstraints.mainWindowMinWidth, WindowConstraints.mainWindowMinHeight),
    );
    await harness.pumpPage(
      tester,
      size: const Size(WindowConstraints.mainWindowMinWidth, WindowConstraints.mainWindowMinHeight),
    );
    await openCreateActionDialog(tester, ptL10n);

    final dialog = tester.widget<ContentDialog>(find.byType(ContentDialog));
    expect(dialog.constraints.maxHeight, lessThanOrEqualTo(WindowConstraints.mainWindowMinHeight));
    expect(find.text(ptL10n.agentActionsFormCreateTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('asks once before discarding unsaved editor changes', (tester) async {
    final harness = AgentActionsPageHarness();
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);

    await tester.enterText(agentActionFormTextBox(ptL10n.agentActionsFormName), 'Dirty draft');
    await tester.pump();

    await tester.tap(find.byIcon(FluentIcons.chrome_close).first);
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsEditorDiscardConfirmTitle), findsOneWidget);

    await tester.tap(find.text(ptL10n.agentActionsEditorDiscardConfirm));
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsEditorDiscardConfirmTitle), findsNothing);
    expect(find.text(ptL10n.agentActionsFormCreateTitle), findsNothing);
  });

  testWidgets('copies a single remote audit row and can jump to history', (tester) async {
    final auditStore = FakeRemoteAuditStore(
      records: <AgentActionRemoteAuditRecord>[
        AgentActionRemoteAuditRecord(
          id: 'audit-ui-copy',
          occurredAtUtc: DateTime.utc(2026, 5, 15, 11),
          rpcMethod: 'agent.action.run',
          outcome: 'success',
          credentialPresent: false,
          actionId: 'action-1',
          executionId: 'execution-1',
        ),
      ],
    );
    final harness = AgentActionsPageHarness(remoteAuditStore: auditStore);
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Correlate audit',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    harness.repository.executions['execution-1'] = AgentActionExecution(
      id: 'execution-1',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime(2026, 5, 15, 9),
      source: AgentActionRequestSource.remoteHub,
      finishedAt: DateTime(2026, 5, 15, 10),
      redactionApplied: true,
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);
    await openTab(tester, ptL10n.agentActionsRemoteAuditTitle);

    expect(find.byType(ToggleButton), findsWidgets);
    expect(find.byKey(const ValueKey<String>('agent_actions_remote_audit_copy_audit-ui-copy')), findsOneWidget);

    await tester.tap(find.text(ptL10n.agentActionsRemoteAuditShowInHistory));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(harness.provider.selectedDefinition?.id, 'action-1');
    expect(find.text(ptL10n.agentActionsHistoryTitle), findsOneWidget);
  });

  testWidgets('wraps PowerShell mode fields instead of overflowing the editor', (tester) async {
    final harness = AgentActionsPageHarness();
    await tester.binding.setSurfaceSize(
      const Size(WindowConstraints.mainWindowMinWidth, WindowConstraints.mainWindowMinHeight),
    );
    await harness.pumpPage(
      tester,
      size: const Size(WindowConstraints.mainWindowMinWidth, WindowConstraints.mainWindowMinHeight),
    );
    await openCreateActionDialog(tester, ptL10n);
    await selectActionFormType(tester, ptL10n, ptL10n.agentActionsTypePowerShell);

    expect(find.byType(AppTextField), findsWidgets);
    expect(
      find.ancestor(
        of: find.text(ptL10n.agentActionsFormPowerShellMode),
        matching: find.byType(Wrap),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });
}
