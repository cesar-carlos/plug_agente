import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

import 'agent_actions_page_test_harness.dart';

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pt'));
  });
  setUp(() async {
    await getIt.reset();
  });
  tearDown(() async {
    await getIt.reset();
  });

  Future<AgentActionsPageHarness> open(WidgetTester tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Example',
      state: AgentActionState.active,
      config: ExecutableActionConfig(executablePath: AgentActionPathReference(originalPath: r'C:\tools\job.exe')),
    );
    await setResponsiveTestWindow(tester, const Size(1400, 900));
    await harness.pumpPage(tester);
    await openActionDetailsDialog(tester, 'action-1');
    await openCreateTriggerDialog(tester, l10n);
    return harness;
  }

  testWidgets('categories limit the type menu and show a description with balanced footer', (tester) async {
    await open(tester);
    final manual = tester.widget<ComboBox<AgentActionTriggerType>>(formComboBox(l10n.agentActionsTriggerFieldType));
    expect(manual.items!.length, 2);
    expect(find.text(l10n.triggerManualDescription), findsOneWidget);
    await selectTriggerType(tester, l10n, l10n.agentActionsTriggerTypeWeekly);
    final weekly = tester.widget<ComboBox<AgentActionTriggerType>>(formComboBox(l10n.agentActionsTriggerFieldType));
    expect(weekly.items!.length, 5);
    expect(find.text(l10n.triggerWeeklyDescription), findsOneWidget);
    final cancel = find.widgetWithText(Button, l10n.agentActionsTriggerCancel).last;
    final save = find.widgetWithText(FilledButton, l10n.agentActionsTriggerSave);
    final surfaceWidth = tester.getSize(find.byKey(const ValueKey('agent_action_trigger_dialog_surface'))).width;
    expect(tester.getSize(cancel).width, lessThan(surfaceWidth / 2));
    expect(tester.getSize(save).width, lessThan(surfaceWidth / 2));
    expect(tester.getRect(cancel).right, lessThan(tester.getRect(save).left));
    expect(tester.getRect(save).left - tester.getRect(cancel).right, lessThanOrEqualTo(16));
  });

  testWidgets('invalid date remains open and focuses the inline error field', (tester) async {
    final harness = await open(tester);
    await selectTriggerType(tester, l10n, l10n.agentActionsTriggerTypeOnce);
    final start = agentActionFormTextBox(l10n.agentActionsTriggerFieldStartAt);
    await tester.enterText(start, '2026-02-31 10:00');
    await tester.tap(find.widgetWithText(FilledButton, l10n.agentActionsTriggerSave));
    await tester.pumpAndSettle();
    expect(harness.repository.triggers, isEmpty);
    expect(find.text(l10n.agentActionsTriggerValidationInvalidDateRange), findsWidgets);
    expect(tester.widget<TextBox>(start).focusNode!.hasFocus, isTrue);
    expect(find.text(l10n.agentActionsTriggerEditorTitleNew), findsOneWidget);
  });

  testWidgets('date and time picker applies values and updates the preview', (tester) async {
    await open(tester);
    await selectTriggerType(tester, l10n, l10n.agentActionsTriggerTypeOnce);
    await tester.tap(find.byTooltip(l10n.triggerPickDateTime).first);
    await tester.pumpAndSettle();
    tester.widget<DatePicker>(find.byType(DatePicker)).onChanged!(DateTime(2035, 6, 15));
    await tester.pump();
    tester.widget<TimePicker>(find.byType(TimePicker)).onChanged!(DateTime(2035, 6, 15, 14, 30));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, l10n.triggerApply));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextBox>(agentActionFormTextBox(l10n.agentActionsTriggerFieldStartAt)).controller!.text,
      '2035-06-15 14:30',
    );
    expect(find.text(l10n.agentActionsTriggerNextRun('2035-06-15 14:30')), findsOneWidget);
    expect(find.text(l10n.triggerPreviewLocal), findsOneWidget);
  });

  testWidgets('expired schedule shows an explicit no-future-run explanation', (tester) async {
    await open(tester);
    await selectTriggerType(tester, l10n, l10n.agentActionsTriggerTypeOnce);
    await tester.enterText(agentActionFormTextBox(l10n.agentActionsTriggerFieldStartAt), '2000-01-01 10:00');
    await tester.pumpAndSettle();
    expect(find.text(l10n.triggerNoFutureRun), findsOneWidget);
  });
}
