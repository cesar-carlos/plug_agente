import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/navigation/app_paged_view.dart';

import 'agent_actions_page_test_harness.dart';

void main() {
  late AppLocalizations l10n;
  setUpAll(() async => l10n = await AppLocalizations.delegate.load(const Locale('pt')));

  Future<void> pumpHarness(WidgetTester tester, AgentActionsPageHarness harness) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await harness.pumpPage(tester);
  }

  testWidgets('editor opens on the identification page', (tester) async {
    final harness = AgentActionsPageHarness();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await pumpHarness(tester, harness);
    await openCreateActionDialog(tester, l10n, expandPolicies: false);
    expect(isAppPageSelected(tester, 'identity'), isTrue);
    expect(isAppPageSelected(tester, 'advanced'), isFalse);
    expect(find.text(l10n.agentActionsEditorActivationSteps), findsOneWidget);
    expect(find.byType(AppPagedView), findsOneWidget);
    expect(find.text(l10n.agentActionsEditorNotificationsTab), findsOneWidget);
    expect(find.text(l10n.pagedViewPrevious), findsOneWidget);
    expect(find.text(l10n.pagedViewPosition(1, 6)), findsNothing);
    expect(filledButtonWithText(l10n.agentActionsFormSave), findsOneWidget);
    expect(
      tester.getCenter(filledButtonWithText(l10n.agentActionsFormSave)).dy,
      closeTo(tester.getCenter(find.text(l10n.pagedViewNext)).dy, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing execution field opens execution and focuses the command', (tester) async {
    final harness = AgentActionsPageHarness();
    await pumpHarness(tester, harness);
    await openCreateActionDialog(tester, l10n, expandPolicies: false);
    await tester.enterText(agentActionFormTextBox(l10n.agentActionsFormName), 'Atualizar estoque');
    await tester.tap(filledButtonWithText(l10n.agentActionsFormSave));
    await tester.pumpAndSettle();

    expect(isAppPageSelected(tester, 'target'), isTrue);
    final command = agentActionFormTextBox(l10n.agentActionsFormCommand);
    expect(tester.widget<TextBox>(command).focusNode!.hasFocus, isTrue);
    expect(find.text(l10n.formFieldRequired(l10n.agentActionsFormCommand)), findsOneWidget);
    expect(harness.repository.definitions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('required errors stay inline and focus the first missing field', (tester) async {
    final harness = AgentActionsPageHarness();
    await pumpHarness(tester, harness);
    await openCreateActionDialog(tester, l10n, expandPolicies: false);
    await tester.tap(filledButtonWithText(l10n.agentActionsFormSave));
    await tester.pumpAndSettle();
    expect(find.byType(ContentDialog), findsOneWidget);
    expect(find.text(l10n.formFieldRequired(l10n.agentActionsFormName)), findsOneWidget);
    expect(tester.widget<TextBox>(agentActionFormTextBox(l10n.agentActionsFormName)).focusNode!.hasFocus, isTrue);
    await tester.enterText(agentActionFormTextBox(l10n.agentActionsFormName), 'Atualizar estoque');
    await tester.pump();
    expect(find.text(l10n.formFieldRequired(l10n.agentActionsFormName)), findsNothing);
    expect(harness.repository.definitions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid advanced policy opens its section and focuses the field', (tester) async {
    final harness = AgentActionsPageHarness();
    await pumpHarness(tester, harness);
    await openCreateActionDialog(tester, l10n, expandPolicies: false);
    await tester.enterText(agentActionFormTextBox(l10n.agentActionsFormName), 'Atualizar estoque');
    await showActionEditorPage(tester, 'target');
    await tester.enterText(agentActionFormTextBox(l10n.agentActionsFormCommand), 'echo ok');
    await showActionEditorPage(tester, 'advanced');
    final queue = agentActionFormTextBox(l10n.agentActionsFormMaxConcurrent);
    await tester.ensureVisible(queue);
    await tester.pumpAndSettle();
    await tester.enterText(queue, '0');
    await showActionEditorPage(tester, 'identity');
    await tester.tap(filledButtonWithText(l10n.agentActionsFormSave));
    await tester.pumpAndSettle();
    expect(isAppPageSelected(tester, 'advanced'), isTrue);
    expect(tester.widget<TextBox>(queue).focusNode!.hasFocus, isTrue);
    expect(find.byType(ContentDialog), findsOneWidget);
    expect(harness.repository.definitions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification-only edits require confirmation before closing', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Atualizar estoque',
      config: CommandLineActionConfig(command: 'echo ok'),
    );
    await pumpHarness(tester, harness);
    await openSelectedActionDialog(tester, expandPolicies: false);
    await showActionEditorPage(tester, 'notifications');
    final notification = find.text(l10n.agentActionsFormNotifyOnSuccess);
    await tester.ensureVisible(notification);
    await tester.pumpAndSettle();
    await tester.tap(notification);
    await tester.pump();
    final close = find.byTooltip(l10n.btnClose).first;
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.text(l10n.agentActionsEditorDiscardConfirmTitle), findsOneWidget);
    await tester.tap(find.text(l10n.agentActionsEditorKeepEditing));
    await tester.pumpAndSettle();
    expect(find.byType(ContentDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('schedule section explains manual-only actions and saving first', (tester) async {
    final harness = AgentActionsPageHarness();
    await pumpHarness(tester, harness);
    await openCreateActionDialog(tester, l10n, expandPolicies: false);
    await showActionEditorPage(tester, 'schedule');
    expect(find.text(l10n.agentActionsEditorScheduleLocalOnly), findsOneWidget);
    await showActionEditorPage(tester, 'identity');
    await selectActionFormType(tester, l10n, l10n.agentActionsTypeExecutable);
    await showActionEditorPage(tester, 'schedule');
    expect(find.text(l10n.agentActionsEditorScheduleSaveFirst), findsOneWidget);
    expect(find.byKey(const ValueKey('agent_action_editor_add_trigger')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('type changes preserve identification and the execution limits', (tester) async {
    final harness = AgentActionsPageHarness();
    await pumpHarness(tester, harness);
    await openCreateActionDialog(tester, l10n, expandPolicies: false);
    await tester.enterText(agentActionFormTextBox(l10n.agentActionsFormName), 'Atualizar estoque');
    await tester.enterText(agentActionFormTextBox(l10n.agentActionsFormDescription), 'Rotina diária');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(agentActionFormComboBox(l10n.agentActionsFormType));
    await tester.pumpAndSettle();
    await selectActionFormType(tester, l10n, l10n.agentActionsTypeExecutable);
    expect(
      tester.widget<TextBox>(agentActionFormTextBox(l10n.agentActionsFormName)).controller!.text,
      'Atualizar estoque',
    );
    expect(
      tester.widget<TextBox>(agentActionFormTextBox(l10n.agentActionsFormDescription)).controller!.text,
      'Rotina diária',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact editor with enlarged text keeps every section usable', (tester) async {
    final harness = AgentActionsPageHarness();
    await tester.binding.setSurfaceSize(const Size(640, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await harness.featureFlags.setEnableRemoteAgentActions(true);
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, l10n, expandPolicies: false);
    await selectActionFormType(tester, l10n, l10n.agentActionsTypeExecutable);
    await showActionEditorPage(tester, 'advanced');
    await showActionEditorPage(tester, 'notifications');
    expect(filledButtonWithText(l10n.agentActionsFormSave), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved executable offers trigger editing and a next-run summary', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Atualizar estoque',
      config: ExecutableActionConfig(executablePath: AgentActionPathReference(originalPath: r'C:\tools\update.exe')),
    );
    harness.repository.triggers['trigger-1'] = AgentActionTrigger(
      id: 'trigger-1',
      actionId: 'action-1',
      type: AgentActionTriggerType.daily,
      nextRunAt: DateTime(2027, 1, 1, 9),
      schedule: const AgentActionTriggerSchedule(timeOfDayMinutes: 540),
    );
    await pumpHarness(tester, harness);
    await openSelectedActionDialog(tester, expandPolicies: false);
    await showActionEditorPage(tester, 'schedule');
    expect(find.textContaining('Próximo disparo:'), findsOneWidget);
    expect(find.text(l10n.agentActionsEditorScheduleHint), findsOneWidget);
    final add = find.byKey(const ValueKey('agent_action_editor_add_trigger'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text(l10n.agentActionsTriggerEditorTitleNew), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
