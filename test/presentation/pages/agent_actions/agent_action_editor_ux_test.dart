import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_editor_section.dart';

import 'agent_actions_page_test_harness.dart';

void main() {
  late AppLocalizations l10n;
  setUpAll(() async => l10n = await AppLocalizations.delegate.load(const Locale('pt')));

  Future<void> pumpHarness(WidgetTester tester, AgentActionsPageHarness harness) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await harness.pumpPage(tester);
  }

  Future<void> toggle(WidgetTester tester, String section) async {
    final header = find
        .descendant(of: find.byKey(ValueKey('agent_action_section_$section')), matching: find.byType(Button))
        .first;
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  testWidgets('editor starts with essential sections open and advanced settings collapsed', (tester) async {
    final harness = AgentActionsPageHarness();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await pumpHarness(tester, harness);
    await openCreateActionDialog(tester, l10n, expandPolicies: false);
    expect(
      tester.widget<AgentActionEditorSection>(find.byKey(const ValueKey('agent_action_section_identity'))).expanded,
      isTrue,
    );
    expect(
      tester.widget<AgentActionEditorSection>(find.byKey(const ValueKey('agent_action_section_target'))).expanded,
      isTrue,
    );
    expect(
      tester.widget<AgentActionEditorSection>(find.byKey(const ValueKey('agent_action_section_limits'))).expanded,
      isTrue,
    );
    expect(
      tester.widget<AgentActionEditorSection>(find.byKey(const ValueKey('agent_action_section_advanced'))).expanded,
      isFalse,
    );
    expect(
      tester
          .widget<AgentActionEditorSection>(find.byKey(const ValueKey('agent_action_section_notifications')))
          .expanded,
      isFalse,
    );
    expect(find.text(l10n.agentActionsEditorActivationSteps), findsOneWidget);
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
    await tester.enterText(agentActionFormTextBox(l10n.agentActionsFormCommand), 'echo ok');
    await toggle(tester, 'advanced');
    final queue = agentActionFormTextBox(l10n.agentActionsFormMaxConcurrent);
    await tester.ensureVisible(queue);
    await tester.pumpAndSettle();
    await tester.enterText(queue, '0');
    await toggle(tester, 'advanced');
    await tester.tap(filledButtonWithText(l10n.agentActionsFormSave));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AgentActionEditorSection>(find.byKey(const ValueKey('agent_action_section_advanced'))).expanded,
      isTrue,
    );
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
    await toggle(tester, 'notifications');
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
    await toggle(tester, 'schedule');
    expect(find.text(l10n.agentActionsEditorScheduleLocalOnly), findsOneWidget);
    await tester.ensureVisible(agentActionFormComboBox(l10n.agentActionsFormType));
    await tester.pumpAndSettle();
    await selectActionFormType(tester, l10n, l10n.agentActionsTypeExecutable);
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
    await toggle(tester, 'advanced');
    await toggle(tester, 'notifications');
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
    await toggle(tester, 'schedule');
    expect(find.textContaining('Próximo disparo:'), findsOneWidget);
    final add = find.byKey(const ValueKey('agent_action_editor_add_trigger'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text(l10n.agentActionsTriggerEditorTitleNew), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
