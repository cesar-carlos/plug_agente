import 'dart:convert';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/use_cases/dispatch_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_captured_output_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/utils/powershell_command_line.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:uuid/uuid.dart';

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

  testWidgets('hides action editor when agent actions feature is disabled', (tester) async {
    final harness = AgentActionsPageHarness();
    await harness.featureFlags.setEnableAgentActions(false);

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    expect(find.text(ptL10n.agentActionsDisabledTitle), findsWidgets);
    expect(find.text(ptL10n.agentActionsFormSave), findsNothing);
    expect(find.text(ptL10n.agentActionsFormCommand), findsNothing);
  });

  testWidgets('renders empty state and opens command line form dialog', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    expect(find.text(ptL10n.navAgentActions), findsWidgets);
    expect(find.text(ptL10n.agentActionsEmptyActions), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormCreateTitle), findsNothing);

    await openCreateActionDialog(tester, ptL10n);

    expect(find.text(ptL10n.agentActionsFormCreateTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormName), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormCommand), findsOneWidget);

    Navigator.pop(tester.element(find.byType(ContentDialog)));
    await tester.pumpAndSettle();

    await openTab(tester, ptL10n.configTabPreferences);

    expect(find.text(ptL10n.agentActionsRetentionTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsRetentionEnvVariables), findsOneWidget);
    expect(find.text(ptL10n.agentActionsRetentionSave), findsOneWidget);
  });

  testWidgets('action editor shows help flyouts for critical fields', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);

    expect(agentActionFormHelpButton(ptL10n.agentActionsFormType), findsOneWidget);
    expect(agentActionFormHelpButton(ptL10n.agentActionsFormState), findsOneWidget);
    expect(agentActionFormHelpButton(ptL10n.agentActionsFormCommand), findsOneWidget);
    expect(agentActionFormHelpButton(ptL10n.agentActionsFormName), findsNothing);
    expect(agentActionFormHelpButtonByKey(ptL10n.agentActionsFormType), findsOneWidget);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == '${ptL10n.agentActionsFormType}. ${ptL10n.agentActionsHelpTypeTitle}' &&
            widget.properties.hint == ptL10n.agentActionsHelpTypeMessage,
      ),
      findsOneWidget,
    );

    await tester.tap(agentActionFormHelpButtonByKey(ptL10n.agentActionsFormType));
    await tester.pumpAndSettle();

    expect(find.byType(FlyoutContent), findsOneWidget);
    expect(find.text(ptL10n.agentActionsHelpTypeTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsHelpTypeMessage), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsHelpTypeTitle), findsNothing);

    await tester.tap(agentActionFormHelpButtonByKey(ptL10n.agentActionsFormType));
    await tester.pumpAndSettle();

    expect(find.byType(FlyoutContent), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.byType(FlyoutContent), findsNothing);
  });

  testWidgets('shows maintenance mode info modal when maintenance toggle is enabled', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    expect(find.text(ptL10n.agentActionsMaintenanceModeInfoTitle), findsNothing);

    await tester.tap(find.byType(ToggleSwitch).first);
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsMaintenanceModeInfoTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsMaintenanceModeInfoMessage), findsOneWidget);
    expect(find.byType(ContentDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, ptL10n.agentActionsMaintenanceMode));
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsMaintenanceModeInfoTitle), findsNothing);
    await openTab(tester, ptL10n.configTabPreferences);
    expect(find.text(ptL10n.agentActionsSummaryMaintenanceActive), findsOneWidget);
  });

  testWidgets('opens new action editor from empty state while maintenance mode is enabled', (tester) async {
    final harness = AgentActionsPageHarness();
    await harness.featureFlags.setEnableAgentActionsMaintenanceMode(true);

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    await tester.tap(find.widgetWithText(FilledButton, ptL10n.agentActionsFormNew).last);
    await tester.pumpAndSettle();

    expect(find.byType(ContentDialog), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormCreateTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens only one action editor when create is triggered twice before next frame', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    final createButton = find.widgetWithText(FilledButton, ptL10n.agentActionsFormNew).first;
    await tester.tap(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(find.byType(ContentDialog), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormCreateTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disables trigger add button while maintenance mode is enabled', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);
    await openActionDetailsDialog(tester, 'action-1');

    final addTrigger = find.descendant(
      of: find.byType(ContentDialog),
      matching: find.widgetWithText(Button, ptL10n.agentActionsTriggerAdd),
    );
    expect(tester.widget<Button>(addTrigger).onPressed, isNotNull);

    await harness.provider.setMaintenanceMode(enabled: true);
    await tester.pumpAndSettle();

    expect(tester.widget<Button>(addTrigger).onPressed, isNull);
  });

  testWidgets('shows remote ad-hoc disabled info when global ad-hoc flag is off', (tester) async {
    final harness = AgentActionsPageHarness();
    await harness.featureFlags.setEnableRemoteAgentActions(true);
    await harness.featureFlags.setEnableRemoteAdHocAgentActions(false);
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Remote action',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    expect(find.text(ptL10n.agentActionsFormRemoteAdHocFeatureDisabledTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormRemoteAdHocFeatureDisabledMessage), findsOneWidget);
  });

  testWidgets('shows production path allowlist error when operational profile is prod and allowlist is empty', (
    tester,
  ) async {
    dotenv.loadFromString(envString: 'AGENT_OPERATIONAL_PROFILE=prod');
    addTearDown(dotenv.clean);

    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'CLI action',
      config: CommandLineActionConfig(command: 'dir'),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2400));
    await harness.pumpPage(tester);

    await openSelectedActionDialog(tester);

    expect(find.text(ptL10n.agentActionsProductionPathAllowlistRequiredTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsProductionPathAllowlistRequiredMessage), findsOneWidget);
  });

  testWidgets('toggles maintenance strict mode checkbox when maintenance is on', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    expect(harness.provider.isMaintenanceStrictMode, isFalse);

    await harness.provider.setMaintenanceMode(enabled: true);
    await tester.pumpAndSettle();

    final strictCheckbox = find.widgetWithText(Checkbox, ptL10n.agentActionsMaintenanceStrictMode);
    expect(strictCheckbox, findsOneWidget);
    expect(tester.widget<Checkbox>(strictCheckbox).checked, isFalse);

    await tester.tap(strictCheckbox);
    await tester.pumpAndSettle();

    expect(harness.provider.isMaintenanceStrictMode, isTrue);
    expect(tester.widget<Checkbox>(strictCheckbox).checked, isTrue);
  });

  testWidgets('keeps actions page stable when resized to narrow width', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    await tester.binding.setSurfaceSize(const Size(920, 900));
    await tester.pumpAndSettle();

    expect(find.text('Run command'), findsWidgets);
    expect(find.byKey(const ValueKey<String>('agent_actions_detail_scroll')), findsNothing);
    expect(find.byKey(const ValueKey<String>('agent_action_definition_more_action-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps actions page stable in compact height viewport', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    harness.repository.executions['execution-1'] = AgentActionExecution(
      id: 'execution-1',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime(2026, 5, 15, 10),
      source: AgentActionRequestSource.localUi,
    );

    await tester.binding.setSurfaceSize(const Size(1200, 680));
    await harness.pumpPage(tester);

    expect(find.text('Run command'), findsWidgets);
    expect(find.byKey(const ValueKey<String>('agent_actions_detail_scroll')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps action editor dialog stable in compact viewport', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(920, 680));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);

    expect(find.text(ptL10n.agentActionsFormCreateTitle), findsOneWidget);
    expect(find.widgetWithText(FilledButton, ptL10n.agentActionsFormSave), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('action editor dialog scrolls with a dedicated controller', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);

    final dialog = find.byType(ContentDialog);
    final scrollbarFinder = find.descendant(
      of: dialog,
      matching: find.byType(Scrollbar),
    );
    final listViewFinder = find.descendant(
      of: dialog,
      matching: find.byType(ListView),
    );

    expect(scrollbarFinder, findsOneWidget);
    expect(listViewFinder, findsOneWidget);

    final scrollbar = tester.widget<Scrollbar>(scrollbarFinder);
    final listView = tester.widget<ListView>(listViewFinder);

    expect(scrollbar.controller, isNotNull);
    expect(listView.controller, same(scrollbar.controller));
    expect(listView.primary, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders triggers section when triggers exist', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    harness.repository.triggers['trig-1'] = const AgentActionTrigger(
      id: 'trig-1',
      actionId: 'action-1',
      type: AgentActionTriggerType.daily,
      name: 'Morning',
      schedule: AgentActionTriggerSchedule(
        timezoneId: 'America/Sao_Paulo',
        ignoreMissedRuns: false,
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    await openActionDetailsDialog(tester, 'action-1');
    await harness.provider.refreshTriggersForSelection();
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsTriggersTitle), findsOneWidget);
    expect(find.text('Morning'), findsOneWidget);
    expect(find.textContaining('America/Sao_Paulo'), findsOneWidget);
    expect(find.textContaining(ptL10n.agentActionsTriggerSummaryCatchUpEnabled), findsOneWidget);
  });

  testWidgets('trigger dialog uses larger desktop surface with fixed footer', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await setResponsiveTestWindow(tester, const Size(1400, 900));
    await harness.pumpPage(tester);
    await openActionDetailsDialog(tester, 'action-1');
    await openCreateTriggerDialog(tester, ptL10n);

    final surface = find.byKey(const ValueKey<String>('agent_action_trigger_dialog_surface'));
    expect(surface, findsOneWidget);
    expect(tester.getSize(surface).width, greaterThan(650));
    expect(tester.getSize(surface).height, greaterThan(540));
    expect(find.widgetWithText(FilledButton, ptL10n.agentActionsTriggerSave), findsOneWidget);
  });

  testWidgets('trigger dialog places paired fields side by side on desktop', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await setResponsiveTestWindow(tester, const Size(1400, 900));
    await harness.pumpPage(tester);
    await openActionDetailsDialog(tester, 'action-1');
    await openCreateTriggerDialog(tester, ptL10n);
    drainPendingFlutterErrors(tester);
    await selectTriggerType(tester, ptL10n, ptL10n.agentActionsTriggerTypeInterval);

    final intervalTopLeft = tester.getTopLeft(agentActionFormTextBox(ptL10n.agentActionsTriggerFieldIntervalMinutes));
    final startTopLeft = tester.getTopLeft(agentActionFormTextBox(ptL10n.agentActionsTriggerFieldStartAtOptional));
    expect((intervalTopLeft.dy - startTopLeft.dy).abs(), lessThan(20));
    expect(startTopLeft.dx, greaterThan(intervalTopLeft.dx));
  });

  testWidgets('trigger dialog stacks paired fields in compact width', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    harness.repository.triggers['trig-1'] = const AgentActionTrigger(
      id: 'trig-1',
      actionId: 'action-1',
      type: AgentActionTriggerType.interval,
      name: 'Every 15 minutes',
      schedule: AgentActionTriggerSchedule(interval: Duration(minutes: 15)),
    );

    await tester.binding.setSurfaceSize(const Size(920, 700));
    await harness.pumpPage(tester);
    await harness.provider.refreshTriggersForSelection();
    await tester.pumpAndSettle();
    await openActionDetailsDialog(tester, 'action-1');
    drainPendingFlutterErrors(tester);
    await tester.tap(find.byKey(const ValueKey<String>('agent_action_trigger_edit_trig-1')));
    await tester.pumpAndSettle();
    drainPendingFlutterErrors(tester);

    final intervalTopLeft = tester.getTopLeft(agentActionFormTextBox(ptL10n.agentActionsTriggerFieldIntervalMinutes));
    final startTopLeft = tester.getTopLeft(agentActionFormTextBox(ptL10n.agentActionsTriggerFieldStartAtOptional));
    expect((intervalTopLeft.dx - startTopLeft.dx).abs(), lessThan(4));
    expect(startTopLeft.dy, greaterThan(intervalTopLeft.dy));
  });

  testWidgets('trigger dialog keeps save action visible while content scrolls', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await setResponsiveTestWindow(tester, const Size(900, 560));
    await harness.pumpPage(tester);
    await openActionDetailsDialog(tester, 'action-1');
    await openCreateTriggerDialog(tester, ptL10n);
    drainPendingFlutterErrors(tester);
    await selectTriggerType(tester, ptL10n, ptL10n.agentActionsTriggerTypeWeekly);

    await tester.drag(
      find.byKey(const ValueKey<String>('agent_action_trigger_dialog_scroll')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, ptL10n.agentActionsTriggerSave), findsOneWidget);
    drainPendingFlutterErrors(tester);
  });

  for (final scenario in <({String label, AgentActionTriggerType type, Future<void> Function(WidgetTester) fill})>[
    (
      label: 'manual',
      type: AgentActionTriggerType.manual,
      fill: (tester) async {},
    ),
    (
      label: 'interval',
      type: AgentActionTriggerType.interval,
      fill: (tester) async {
        await tester.enterText(agentActionFormTextBox(ptL10n.agentActionsTriggerFieldIntervalMinutes), '15');
      },
    ),
    (
      label: 'weekly',
      type: AgentActionTriggerType.weekly,
      fill: (tester) async {
        await tester.enterText(agentActionFormTextBox(ptL10n.agentActionsTriggerFieldTimeOfDay), '08:30');
        await tester.tap(find.widgetWithText(Checkbox, ptL10n.agentActionsTriggerWeekdayMon));
      },
    ),
    (
      label: 'monthly',
      type: AgentActionTriggerType.monthly,
      fill: (tester) async {
        await tester.enterText(agentActionFormTextBox(ptL10n.agentActionsTriggerFieldTimeOfDay), '08:30');
        await tester.enterText(agentActionFormTextBox(ptL10n.agentActionsTriggerFieldDayOfMonth), '15');
      },
    ),
  ]) {
    testWidgets('saves ${scenario.label} trigger after layout changes', (tester) async {
      final harness = AgentActionsPageHarness();
      harness.repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );

      await setResponsiveTestWindow(tester, const Size(1400, 900));
      await harness.pumpPage(tester);
      await openActionDetailsDialog(tester, 'action-1');
      await openCreateTriggerDialog(tester, ptL10n);
      await selectTriggerType(tester, ptL10n, triggerTypeTestLabel(scenario.type, ptL10n));
      await scenario.fill(tester);

      await tester.tap(find.widgetWithText(FilledButton, ptL10n.agentActionsTriggerSave));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(harness.repository.triggers, hasLength(1));
      expect(harness.repository.triggers.values.single.type, scenario.type);
      expect(find.text(ptL10n.agentActionsTriggerEditorTitleNew), findsNothing);
    });
  }

  testWidgets('saves a command line action from the form', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1600, 2600));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);

    final nameField = agentActionFormTextBox(ptL10n.agentActionsFormName);
    final commandField = agentActionFormTextBox(ptL10n.agentActionsFormCommand);
    expect(nameField, findsOneWidget);
    expect(commandField, findsOneWidget);

    await tester.enterText(nameField, 'Run dir');
    await tester.enterText(commandField, 'dir');

    final saveAction = filledButtonWithText(ptL10n.agentActionsFormSave);
    tester.widget<FilledButton>(saveAction).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(harness.repository.definitions, hasLength(1));
    expect(find.text('Run dir'), findsWidgets);
    expect(find.byType(ContentDialog), findsNothing);
  });

  testWidgets('shows PowerShell in action type dropdown', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);

    await tester.tap(agentActionFormComboBox(ptL10n.agentActionsFormType));
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsTypePowerShell), findsOneWidget);
  });

  testWidgets('saves a PowerShell inline action as command line config', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1600, 2600));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);
    await selectActionFormType(tester, ptL10n, ptL10n.agentActionsTypePowerShell);

    await tester.enterText(agentActionFormTextBox(ptL10n.agentActionsFormName), 'Run PowerShell');
    await tester.enterText(
      agentActionFormTextBox(ptL10n.agentActionsFormPowerShellCommand),
      'Write-Output "ok" | Out-String',
    );

    tester.widget<FilledButton>(filledButtonWithText(ptL10n.agentActionsFormSave)).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(harness.repository.definitions, hasLength(1));
    final definition = harness.repository.definitions.values.single;
    expect(definition.type, AgentActionType.commandLine);
    final config = definition.config;
    expect(config, isA<CommandLineActionConfig>());
    expect(
      (config as CommandLineActionConfig).command,
      PowerShellCommandLine.wrapInlineCommand('Write-Output "ok" | Out-String'),
    );
    expect(find.text(ptL10n.agentActionsTypePowerShell), findsWidgets);
    expect(find.byType(ContentDialog), findsNothing);
  });

  testWidgets('saves a PowerShell 7 inline action as command line config', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1600, 2600));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);
    await selectActionFormType(tester, ptL10n, ptL10n.agentActionsTypePowerShell);
    await selectPowerShellExecutable(tester, ptL10n, ptL10n.agentActionsFormPowerShellExecutablePwsh);

    await tester.enterText(agentActionFormTextBox(ptL10n.agentActionsFormName), 'Run pwsh');
    await tester.enterText(
      agentActionFormTextBox(ptL10n.agentActionsFormPowerShellCommand),
      'Write-Output "ok" & whoami',
    );

    tester.widget<FilledButton>(filledButtonWithText(ptL10n.agentActionsFormSave)).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(harness.repository.definitions, hasLength(1));
    final definition = harness.repository.definitions.values.single;
    final config = definition.config;
    expect(config, isA<CommandLineActionConfig>());
    expect(
      (config as CommandLineActionConfig).command,
      PowerShellCommandLine.wrapInlineCommand(
        'Write-Output "ok" & whoami',
        executable: PowerShellCommandLine.powerShell7Executable,
      ),
    );
  });

  testWidgets('saves a PowerShell script action as script config', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1600, 2600));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);
    await selectActionFormType(tester, ptL10n, ptL10n.agentActionsTypePowerShell);
    await selectPowerShellMode(tester, ptL10n, ptL10n.agentActionsFormPowerShellModeScript);

    await tester.enterText(agentActionFormTextBox(ptL10n.agentActionsFormName), 'Run script');
    await tester.enterText(agentActionFormTextBox(ptL10n.agentActionsFormPowerShellScriptPath), r'C:\Jobs\backup.ps1');
    await tester.enterText(agentActionFormTextBox(ptL10n.agentActionsFormArguments), '-Verbose');

    tester.widget<FilledButton>(filledButtonWithText(ptL10n.agentActionsFormSave)).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(harness.repository.definitions, hasLength(1));
    final definition = harness.repository.definitions.values.single;
    expect(definition.type, AgentActionType.script);
    final config = definition.config;
    expect(config, isA<ScriptActionConfig>());
    expect((config as ScriptActionConfig).scriptPath.originalPath, r'C:\Jobs\backup.ps1');
    expect(config.arguments, ['-Verbose']);
    expect(config.interpreterPath, isNull);
    expect(find.byType(ContentDialog), findsNothing);
  });

  testWidgets('saves a PowerShell 7 script action as script config with pwsh interpreter', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1600, 2600));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);
    await selectActionFormType(tester, ptL10n, ptL10n.agentActionsTypePowerShell);
    await selectPowerShellMode(tester, ptL10n, ptL10n.agentActionsFormPowerShellModeScript);
    await selectPowerShellExecutable(tester, ptL10n, ptL10n.agentActionsFormPowerShellExecutablePwsh);

    await tester.enterText(agentActionFormTextBox(ptL10n.agentActionsFormName), 'Run pwsh script');
    await tester.enterText(agentActionFormTextBox(ptL10n.agentActionsFormPowerShellScriptPath), r'C:\Jobs\backup.ps1');

    tester.widget<FilledButton>(filledButtonWithText(ptL10n.agentActionsFormSave)).onPressed!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final definition = harness.repository.definitions.values.single;
    final config = definition.config;
    expect(config, isA<ScriptActionConfig>());
    expect(
      (config as ScriptActionConfig).interpreterPath?.originalPath,
      PowerShellCommandLine.powerShell7Executable,
    );
  });

  testWidgets('opens existing ps1 script action in PowerShell script mode', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'PowerShell script',
      config: ScriptActionConfig(
        scriptPath: AgentActionPathReference(originalPath: r'C:\Jobs\backup.ps1'),
        arguments: ['-Verbose'],
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 1800));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    expect(find.text(ptL10n.agentActionsFormEditPowerShellTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormPowerShellModeScript), findsOneWidget);
    final scriptPathField = tester.widget<TextBox>(
      agentActionFormTextBox(ptL10n.agentActionsFormPowerShellScriptPath),
    );
    expect(scriptPathField.controller?.text, r'C:\Jobs\backup.ps1');
  });

  testWidgets('shows action type as read-only when editing existing action', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Command line',
      config: CommandLineActionConfig(command: 'whoami'),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 1800));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    expect(
      agentActionFormComboBoxByKey('agent_action_editor_type_dropdown'),
      findsNothing,
    );
    final typeField = tester.widget<TextBox>(
      agentActionFormTextBoxByKey('agent_action_editor_type_dropdown'),
    );
    expect(typeField.readOnly, isTrue);
    expect(typeField.controller?.text, ptL10n.agentActionsTypeCommandLine);
  });

  testWidgets('opens generated PowerShell command line action in inline mode', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = AgentActionDefinition(
      id: 'action-1',
      name: 'PowerShell inline',
      config: CommandLineActionConfig(
        command: PowerShellCommandLine.wrapInlineCommand('Write-Output "ok" & whoami'),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 1800));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    expect(find.text(ptL10n.agentActionsFormEditPowerShellTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormPowerShellModeCommand), findsOneWidget);
    expect(
      agentActionFormComboBoxByKey('agent_action_editor_powershell_mode_dropdown'),
      findsNothing,
    );
    final modeField = tester.widget<TextBox>(
      agentActionFormTextBoxByKey('agent_action_editor_powershell_mode_dropdown'),
    );
    expect(modeField.readOnly, isTrue);
    expect(modeField.controller?.text, ptL10n.agentActionsFormPowerShellModeCommand);
    final commandField = tester.widget<TextBox>(
      agentActionFormTextBox(ptL10n.agentActionsFormPowerShellCommand),
    );
    expect(commandField.controller?.text, 'Write-Output "ok" & whoami');
  });

  testWidgets('opens generated PowerShell 7 command line action in inline mode', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = AgentActionDefinition(
      id: 'action-1',
      name: 'PowerShell 7 inline',
      config: CommandLineActionConfig(
        command: PowerShellCommandLine.wrapInlineCommand(
          'Write-Output "ok"',
          executable: PowerShellCommandLine.powerShell7Executable,
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 1800));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    expect(find.text(ptL10n.agentActionsFormEditPowerShellTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormPowerShellExecutablePwsh), findsOneWidget);
    final commandField = tester.widget<TextBox>(
      agentActionFormTextBox(ptL10n.agentActionsFormPowerShellCommand),
    );
    expect(commandField.controller?.text, 'Write-Output "ok"');
  });

  testWidgets('opens existing ps1 script action with pwsh interpreter in PowerShell 7 script mode', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'PowerShell 7 script',
      config: ScriptActionConfig(
        scriptPath: AgentActionPathReference(originalPath: r'C:\Jobs\backup.ps1'),
        interpreterPath: AgentActionPathReference(originalPath: 'pwsh.exe'),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 1800));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    expect(find.text(ptL10n.agentActionsFormEditPowerShellTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormPowerShellModeScript), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormPowerShellExecutablePwsh), findsOneWidget);
  });

  testWidgets('keeps action dialog open when validation fails', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);

    tester.widget<FilledButton>(filledButtonWithText(ptL10n.agentActionsFormSave)).onPressed!.call();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(ContentDialog), findsNWidgets(2));
    expect(find.text(ptL10n.agentActionsValidationTitle), findsOneWidget);
    expect(
      find.textContaining(ptL10n.formFieldRequired(ptL10n.agentActionsFormName)),
      findsOneWidget,
    );
    expect(
      find.textContaining(ptL10n.formFieldRequired(ptL10n.agentActionsFormCommand)),
      findsOneWidget,
    );
    expect(harness.repository.definitions, isEmpty);

    Navigator.pop(tester.element(find.text(ptL10n.agentActionsValidationTitle)));
    await tester.pumpAndSettle();

    expect(find.byType(ContentDialog), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormCreateTitle), findsOneWidget);
  });

  testWidgets('renders developer form for selected developer action', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = AgentActionDefinition(
      id: 'action-1',
      name: 'Transmitir Data7',
      state: AgentActionState.active,
      config: DeveloperActionConfig.data7Executor(
        executorPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Executor.exe',
        ),
        projectPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
        ),
        data7ConfigPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Data7.Config',
        ),
        connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
        connectionLabel: 'Estacao',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    expect(find.text(ptL10n.agentActionsFormEditDeveloperTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormExecutorPath), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormProjectPath), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormData7ConfigPath), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormConnectionId), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormReloadConnections), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormConnectionLabel), findsOneWidget);
    expect(
      find.text(ptL10n.agentActionsFormUseDefaultExecutorPath),
      findsOneWidget,
    );
    expect(
      find.text(ptL10n.agentActionsFormUseDefaultConfigBinPath),
      findsOneWidget,
    );
    expect(
      find.text(ptL10n.agentActionsFormUseDefaultConfigRootPath),
      findsOneWidget,
    );
    expect(find.byIcon(FluentIcons.open_file), findsNWidgets(3));
    expect(find.text('Estacao'), findsAtLeastNWidgets(1));
  });

  testWidgets('applies default Data7 config shortcut', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = AgentActionDefinition(
      id: 'action-1',
      name: 'Transmitir Data7',
      state: AgentActionState.active,
      config: DeveloperActionConfig.data7Executor(
        executorPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Executor.exe',
        ),
        projectPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
        ),
        data7ConfigPath: const AgentActionPathReference(
          originalPath: r'C:\Temp\Data7.Config',
        ),
        connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
        connectionLabel: 'Estacao',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    final configPathField = agentActionFormTextBox(ptL10n.agentActionsFormData7ConfigPath);
    final shortcutButton = find.ancestor(
      of: find.text(ptL10n.agentActionsFormUseDefaultConfigBinPath),
      matching: find.byType(Button),
    );
    await tester.ensureVisible(shortcutButton);
    await tester.tap(shortcutButton);
    await tester.pumpAndSettle();

    expect(tester.widget<TextBox>(configPathField).controller?.text, r'C:\Data7\bin\Data7.Config');
    expect(
      find.text(ptL10n.agentActionsFormData7ConfigPathHintDefaultBin),
      findsOneWidget,
    );
  });

  testWidgets('shows developer binary path warnings for unexpected file names', (
    tester,
  ) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = AgentActionDefinition(
      id: 'action-1',
      name: 'Transmitir Data7',
      state: AgentActionState.active,
      config: DeveloperActionConfig.data7Executor(
        executorPath: const AgentActionPathReference(
          originalPath: r'C:\Temp\Executor.bat',
        ),
        projectPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\Transmissao\Transmissor.txt',
        ),
        data7ConfigPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Data7.txt',
        ),
        connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
        connectionLabel: 'Estacao',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    expect(
      find.text(ptL10n.agentActionsFormExecutorPathHintExpectedFileName),
      findsOneWidget,
    );
    expect(
      find.text(ptL10n.agentActionsFormProjectPathHintExpectedExtension),
      findsOneWidget,
    );
  });

  testWidgets('shows missing file warnings for developer paths', (tester) async {
    final tempRoot = Directory.systemTemp.createTempSync('agent-actions-page');
    addTearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    final missingExecutorPath = '${tempRoot.path}\\missing\\Executor.exe';
    final missingProjectPath = '${tempRoot.path}\\missing\\Transmissor.7Proj';
    final missingConfigPath = '${tempRoot.path}\\missing\\Data7.Config';

    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = AgentActionDefinition(
      id: 'action-1',
      name: 'Transmitir Data7',
      state: AgentActionState.active,
      config: DeveloperActionConfig.data7Executor(
        executorPath: AgentActionPathReference(originalPath: missingExecutorPath),
        projectPath: AgentActionPathReference(originalPath: missingProjectPath),
        data7ConfigPath: AgentActionPathReference(originalPath: missingConfigPath),
        connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
        connectionLabel: 'Estacao',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    expect(
      find.text(ptL10n.agentActionsFormExecutorPathHintMissing),
      findsOneWidget,
    );
    expect(
      find.text(ptL10n.agentActionsFormProjectPathHintMissing),
      findsOneWidget,
    );
  });

  testWidgets('shows resolved config path when lookup uses a different file', (
    tester,
  ) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = AgentActionDefinition(
      id: 'action-1',
      name: 'Transmitir Data7',
      state: AgentActionState.active,
      config: DeveloperActionConfig.data7Executor(
        executorPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Executor.exe',
        ),
        projectPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
        ),
        data7ConfigPath: const AgentActionPathReference(
          originalPath: r'C:\Temp\Custom\Data7.Config',
        ),
        connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
        connectionLabel: 'Estacao',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    expect(
      find.text(
        ptL10n.agentActionsFormLoadedConfigPath(r'C:\Data7\bin\Data7.Config'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows redacted preview after testing developer action', (
    tester,
  ) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = AgentActionDefinition(
      id: 'action-1',
      name: 'Transmitir Data7',
      state: AgentActionState.active,
      config: DeveloperActionConfig.data7Executor(
        executorPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Executor.exe',
        ),
        projectPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
        ),
        data7ConfigPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Data7.Config',
        ),
        connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
        connectionLabel: 'Estacao',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    await tester.tap(find.text(ptL10n.agentActionsTestSelected));
    await tester.pumpAndSettle();
    await openActionDetailsDialog(tester, 'action-1');

    expect(find.byKey(const ValueKey('agent_actions_test_preview')), findsOneWidget);
    expect(find.text(ptL10n.agentActionsTestPreviewTitle), findsOneWidget);
    expect(
      find.text(r'C:\Data7\bin\Executor.exe -p *** -c ***'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '${ptL10n.agentActionsTestPreviewDiagnosticConnectionLabel}: Estacao',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('should show empty hint when developer connection search has no matches', (
    tester,
  ) async {
    final harness = AgentActionsPageHarness(
      developerConnectionGateway: MultiDeveloperData7ConnectionGateway(),
    );
    harness.repository.definitions['action-1'] = AgentActionDefinition(
      id: 'action-1',
      name: 'Transmitir Data7',
      state: AgentActionState.active,
      config: DeveloperActionConfig.data7Executor(
        executorPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Executor.exe',
        ),
        projectPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
        ),
        data7ConfigPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Data7.Config',
        ),
        connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
        connectionLabel: 'Estacao',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    await tester.enterText(
      agentActionFormTextBox(ptL10n.agentActionsFormConnectionSearch),
      'zz-no-match',
    );
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsFormConnectionFilterEmpty), findsOneWidget);
  });

  testWidgets('warns when saved developer connection changed', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = AgentActionDefinition(
      id: 'action-1',
      name: 'Transmitir Data7',
      state: AgentActionState.active,
      config: DeveloperActionConfig.data7Executor(
        executorPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Executor.exe',
        ),
        projectPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
        ),
        data7ConfigPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Data7.Config',
        ),
        connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
        connectionLabel: 'Estacao',
        connectionSnapshotHash: 'hash-antigo',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    expect(find.byKey(const ValueKey('agent_actions_developer_connection_changed_info_bar')), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormConnectionChangedTitle), findsOneWidget);
    expect(
      find.text(ptL10n.agentActionsFormConnectionChangedMessage),
      findsOneWidget,
    );
  });

  testWidgets('warns when typed developer connection id is outside loaded catalog', (
    tester,
  ) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = AgentActionDefinition(
      id: 'action-1',
      name: 'Transmitir Data7',
      state: AgentActionState.active,
      config: DeveloperActionConfig.data7Executor(
        executorPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Executor.exe',
        ),
        projectPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
        ),
        data7ConfigPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Data7.Config',
        ),
        connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
        connectionLabel: 'Estacao',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    await tester.enterText(
      agentActionFormTextBox(ptL10n.agentActionsFormConnectionId),
      '00000000-0000-0000-0000-000000000000',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('agent_actions_developer_connection_unknown_info_bar')), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormConnectionUnknownTitle), findsOneWidget);
    expect(
      find.text(ptL10n.agentActionsFormConnectionUnknownMessage),
      findsOneWidget,
    );
  });

  testWidgets('warns when saved developer connection no longer exists', (
    tester,
  ) async {
    final harness = AgentActionsPageHarness(
      developerConnectionGateway: MissingDeveloperData7ConnectionGateway(),
    );
    harness.repository.definitions['action-1'] = AgentActionDefinition(
      id: 'action-1',
      name: 'Transmitir Data7',
      state: AgentActionState.active,
      config: DeveloperActionConfig.data7Executor(
        executorPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Executor.exe',
        ),
        projectPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
        ),
        data7ConfigPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Data7.Config',
        ),
        connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
        connectionLabel: 'Estacao',
        connectionSnapshotHash: 'hash-estacao',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(
      agentActionFormTextBox(ptL10n.agentActionsFormConnectionId),
      '34512A51-672C-4ECE-9991-F43E175E7A8B',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('agent_actions_developer_connection_missing_info_bar')), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormConnectionMissingTitle), findsOneWidget);
    expect(
      find.text(ptL10n.agentActionsFormConnectionMissingMessage),
      findsOneWidget,
    );
  });

  testWidgets('renders execution diagnostics and cancels running execution', (
    tester,
  ) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    harness.repository.executions['execution-1'] = AgentActionExecution(
      id: 'execution-1',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.running,
      requestedAt: DateTime(2026, 5, 15, 8, 30),
      source: AgentActionRequestSource.localUi,
      idempotencyKey: 'idem-remote-1',
      requestedBy: 'hub-tester',
      traceId: 'trace-abc',
      triggerId: 'trigger-1',
      triggerType: AgentActionTriggerType.manual,
      triggeredAt: DateTime(2026, 5, 15, 8, 30, 1),
      queueStartedAt: DateTime(2026, 5, 15, 8, 30, 2),
      processStartedAt: DateTime(2026, 5, 15, 8, 31),
      exitCode: 2,
      pid: 1234,
      processExecutable: 'cmd.exe',
      processArgumentCount: 2,
      processCommandPreview: 'cmd.exe /C [REDACTED_COMMAND]',
      definitionSnapshotHash: 'sha256:def-snapshot',
      contextHash: 'sha256:ctx-hash',
      redactionApplied: true,
      failureCode: AgentActionFailureCode.exitCodeRejected,
      failurePhase: 'process_exit',
      stdoutText: 'safe stdout',
      stderrText: 'safe stderr',
      stderrTruncated: true,
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openTab(tester, ptL10n.agentActionsHistoryTitle);

    expect(find.text('Run command'), findsWidgets);
    expect(find.text(ptL10n.agentActionsDiagnosticsTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsDiagnosticsCopySupport), findsOneWidget);
    expect(
      find.textContaining('${ptL10n.agentActionsDiagnosticsQueueStartedAt}:', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('${ptL10n.agentActionsDiagnosticsIdempotencyKey}: idem-remote-1', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('${ptL10n.agentActionsDiagnosticsRequestedBy}: hub-tester', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('${ptL10n.agentActionsDiagnosticsTraceId}: trace-abc', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('${ptL10n.agentActionsDiagnosticsTriggerId}: trigger-1', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('${ptL10n.agentActionsDiagnosticsTriggerType}:', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('${ptL10n.agentActionsDiagnosticsTriggeredAt}:', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('1234', findRichText: true), findsOneWidget);
    expect(find.textContaining('cmd.exe', findRichText: true), findsWidgets);
    expect(
      find.textContaining('[REDACTED_COMMAND]', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '${ptL10n.agentActionsDiagnosticsDefinitionSnapshotHash}: sha256:def-snapshot',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '${ptL10n.agentActionsDiagnosticsContextHash}: sha256:ctx-hash',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '${ptL10n.agentActionsDiagnosticsRedactionApplied}: ${ptL10n.agentActionsDiagnosticsValueYes}',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '${ptL10n.agentActionsDiagnosticsFailureCode}: ACTION_EXIT_CODE_REJECTED',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '${ptL10n.agentActionsDiagnosticsFailurePhase}: ${ptL10n.agentActionsFailurePhaseProcessExit}',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text(ptL10n.agentActionsDiagnosticsCorrectiveAction), findsOneWidget);
    expect(
      find.textContaining(
        ptL10n.agentActionsDiagnosticsCorrectiveExitCode,
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('safe stdout', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('safe stderr', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(ptL10n.agentActionsDiagnosticsTruncated),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(FluentIcons.cancel));
    await tester.pump();
    while (harness.provider.isLoading || harness.provider.hasCancellationInProgress('execution-1')) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(
      harness.repository.executions['execution-1']?.status,
      AgentActionExecutionStatus.killed,
    );
    expect(find.text(ptL10n.agentActionsStatusKilled), findsOneWidget);
  });

  testWidgets('should load chunked stdout on demand in execution diagnostics', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Chunked output',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    const chunkMarkerStart = '@CHUNK_START@';
    const chunkMarkerEnd = '@CHUNK_END@';
    final chunkedStdout = '$chunkMarkerStart${'o' * 80000}$chunkMarkerEnd';
    harness.repository.setChunkedCapturedOutput(
      executionId: 'exec-chunk',
      stream: AgentActionCapturedOutputConstants.stdoutStream,
      text: chunkedStdout,
    );
    harness.repository.executions['exec-chunk'] = AgentActionExecution(
      id: 'exec-chunk',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime(2026, 5, 15, 9),
      source: AgentActionRequestSource.localUi,
      finishedAt: DateTime(2026, 5, 15, 9, 5),
      stdoutStoredInChunks: true,
      redactionApplied: true,
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openTab(tester, ptL10n.agentActionsHistoryTitle);

    expect(find.text('Chunked output'), findsWidgets);
    expect(
      find.textContaining(ptL10n.agentActionsExecutionOutputInChunks, findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '${ptL10n.agentActionsDiagnosticsStdout} (${ptL10n.agentActionsDiagnosticsStoredInChunks})',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.textContaining(chunkMarkerStart, findRichText: true), findsOneWidget);
    expect(find.textContaining(chunkMarkerEnd, findRichText: true), findsNothing);
    expect(find.text(ptL10n.agentActionsDiagnosticsLoadMoreStdout), findsOneWidget);

    final secondPage = await harness.provider.sliceCapturedOutput(
      executionId: 'exec-chunk',
      stream: AgentActionCapturedOutputConstants.stdoutStream,
      offsetUtf8: AgentActionRpcConstants.defaultMaxOutputBytesPerStream,
    );
    expect(secondPage.isSuccess(), isTrue);
    expect(secondPage.getOrThrow().text, contains(chunkMarkerEnd));
  });

  testWidgets('should disable unavailable action types in create form type dropdown', (tester) async {
    final guard = AgentActionRuntimeStateGuard()
      ..markDegraded(
        unavailableActionTypes: {AgentActionType.developer},
        reason: 'developer-runner-missing',
      );
    final harness = AgentActionsPageHarness(runtimeStateGuard: guard);

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);

    final typeCombo = agentActionFormComboBox(ptL10n.agentActionsFormType);
    expect(typeCombo, findsOneWidget);

    await tester.tap(typeCombo);
    await tester.pumpAndSettle();

    expect(
      find.text(
        '${ptL10n.agentActionsTypeDeveloper} (${ptL10n.agentActionsRiskRunnerUnavailable})',
      ),
      findsOneWidget,
    );
  });

  testWidgets('PowerShell create form defaults to script mode when command line runner is unavailable', (tester) async {
    final guard = AgentActionRuntimeStateGuard()
      ..markDegraded(
        unavailableActionTypes: {AgentActionType.commandLine},
        reason: 'command-runner-missing',
      );
    final harness = AgentActionsPageHarness(runtimeStateGuard: guard);

    await tester.binding.setSurfaceSize(const Size(1600, 1600));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);
    await selectActionFormType(tester, ptL10n, ptL10n.agentActionsTypePowerShell);

    expect(find.text(ptL10n.agentActionsFormPowerShellModeScript), findsOneWidget);
    await tester.tap(agentActionFormComboBox(ptL10n.agentActionsFormPowerShellMode));
    await tester.pumpAndSettle();
    expect(
      find.text(
        '${ptL10n.agentActionsFormPowerShellModeCommand} (${ptL10n.agentActionsRiskRunnerUnavailable})',
      ),
      findsOneWidget,
    );
  });

  testWidgets('PowerShell create form defaults to command mode when script runner is unavailable', (tester) async {
    final guard = AgentActionRuntimeStateGuard()
      ..markDegraded(
        unavailableActionTypes: {AgentActionType.script},
        reason: 'script-runner-missing',
      );
    final harness = AgentActionsPageHarness(runtimeStateGuard: guard);

    await tester.binding.setSurfaceSize(const Size(1600, 1600));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);
    await selectActionFormType(tester, ptL10n, ptL10n.agentActionsTypePowerShell);

    expect(find.text(ptL10n.agentActionsFormPowerShellModeCommand), findsOneWidget);
    await tester.tap(agentActionFormComboBox(ptL10n.agentActionsFormPowerShellMode));
    await tester.pumpAndSettle();
    expect(
      find.text(
        '${ptL10n.agentActionsFormPowerShellModeScript} (${ptL10n.agentActionsRiskRunnerUnavailable})',
      ),
      findsOneWidget,
    );
  });

  testWidgets('PowerShell action type is unavailable when both underlying runners are unavailable', (tester) async {
    final guard = AgentActionRuntimeStateGuard()
      ..markDegraded(
        unavailableActionTypes: {AgentActionType.commandLine, AgentActionType.script},
        reason: 'powershell-runners-missing',
      );
    final harness = AgentActionsPageHarness(runtimeStateGuard: guard);

    await tester.binding.setSurfaceSize(const Size(1600, 1600));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);

    await tester.tap(agentActionFormComboBox(ptL10n.agentActionsFormType));
    await tester.pumpAndSettle();

    expect(
      find.text(
        '${ptL10n.agentActionsTypePowerShell} (${ptL10n.agentActionsRiskRunnerUnavailable})',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows runner unavailable chip and info bar when subsystem is degraded', (tester) async {
    final guard = AgentActionRuntimeStateGuard()
      ..markDegraded(
        unavailableActionTypes: {AgentActionType.commandLine},
        reason: 'runner-missing',
      );
    final harness = AgentActionsPageHarness(runtimeStateGuard: guard);
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Blocked command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openActionDetailsDialog(tester, 'action-1');

    expect(find.text(ptL10n.agentActionsRiskRunnerUnavailable), findsWidgets);
    expect(find.text(ptL10n.agentActionsActionTypeUnavailableTitle), findsOneWidget);
    expect(find.textContaining('Linha de comando', findRichText: true), findsWidgets);
    expect(harness.provider.canRunSelected, isFalse);
  });

  testWidgets('should filter saved actions list by type in the UI', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['cmd'] = const AgentActionDefinition(
      id: 'cmd',
      name: 'Backup command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    harness.repository.definitions['email'] = const AgentActionDefinition(
      id: 'email',
      name: 'Notify ops',
      state: AgentActionState.active,
      config: EmailActionConfig(
        smtpProfileId: 'smtp-local',
        from: 'agent@example.com',
        to: <String>['ops@example.com'],
        subjectTemplate: 'Done',
        bodyTemplate: 'Finished',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);

    harness.provider.selectAction('email');
    harness.provider.setDefinitionTypeFilter(AgentActionType.email);
    await tester.pumpAndSettle();

    expect(find.text('Backup command'), findsNothing);
    expect(find.text('Notify ops'), findsWidgets);
  });

  testWidgets('clears saved action filters from the grid controls', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['cmd'] = const AgentActionDefinition(
      id: 'cmd',
      name: 'Backup command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    harness.repository.definitions['email'] = const AgentActionDefinition(
      id: 'email',
      name: 'Notify ops',
      state: AgentActionState.paused,
      config: EmailActionConfig(
        smtpProfileId: 'smtp-local',
        from: 'agent@example.com',
        to: <String>['ops@example.com'],
        subjectTemplate: 'Done',
        bodyTemplate: 'Finished',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);

    harness.provider.selectAction('email');
    harness.provider
      ..setDefinitionTypeFilter(AgentActionType.email)
      ..setDefinitionStateFilter(AgentActionState.paused)
      ..setDefinitionSearchQuery('notify');
    await tester.pumpAndSettle();

    expect(find.text('Backup command'), findsNothing);
    expect(find.text('Notify ops'), findsWidgets);

    await tester.tap(find.widgetWithText(Button, ptL10n.ctButtonClearFilters));
    await tester.pumpAndSettle();

    expect(harness.provider.hasDefinitionListFilters, isFalse);
    expect(find.text('Backup command'), findsWidgets);
    expect(find.text('Notify ops'), findsWidgets);
  });

  testWidgets('restores persisted action page tab and filters', (tester) async {
    final harness = AgentActionsPageHarness();
    await harness.appSettingsStore.setValues({
      'agent_actions.ui.selected_tab': 'history',
      'agent_actions.ui.definition_type_filter': AgentActionType.email.name,
      'agent_actions.ui.definition_state_filter': AgentActionState.paused.name,
      'agent_actions.ui.definition_search': 'notify',
      'agent_actions.ui.history_status_filter': AgentActionExecutionStatus.failed.name,
      'agent_actions.ui.history_source_filter': AgentActionRequestSource.localUi.name,
      'agent_actions.ui.history_period_filter': AgentActionHistoryPeriod.last24Hours.name,
      'agent_actions.ui.history_search': 'execution-2',
    });
    harness.repository.definitions['email'] = const AgentActionDefinition(
      id: 'email',
      name: 'Notify ops',
      state: AgentActionState.paused,
      config: EmailActionConfig(
        smtpProfileId: 'smtp-local',
        from: 'agent@example.com',
        to: <String>['ops@example.com'],
        subjectTemplate: 'Done',
        bodyTemplate: 'Finished',
      ),
    );
    harness.repository.definitions['cmd'] = const AgentActionDefinition(
      id: 'cmd',
      name: 'Backup command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);

    expect(find.text(ptL10n.agentActionsHistoryFilterStatus), findsOneWidget);
    expect(harness.provider.definitionTypeFilter, AgentActionType.email);
    expect(harness.provider.definitionStateFilter, AgentActionState.paused);
    expect(harness.provider.definitionSearchQuery, 'notify');
    expect(harness.provider.historyStatusFilter, AgentActionExecutionStatus.failed);
    expect(harness.provider.historySourceFilter, AgentActionRequestSource.localUi);
    expect(harness.provider.historyPeriodFilter, AgentActionHistoryPeriod.last24Hours);
    expect(harness.provider.historySearchQuery, 'execution-2');

    await openTab(tester, ptL10n.agentActionsSummaryActions);

    expect(find.text('Notify ops'), findsWidgets);
    expect(find.text('Backup command'), findsNothing);
  });

  testWidgets('runs, tests and deletes an action from row commands', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);

    final row = find.byKey(const ValueKey<String>('agent_action_definition_row_action-1'));
    await tester.tap(find.descendant(of: row, matching: find.byIcon(FluentIcons.play)));
    await tester.pumpAndSettle();

    expect(harness.repository.executions.values.any((execution) => execution.actionId == 'action-1'), isTrue);

    await tester.tap(find.descendant(of: row, matching: find.byIcon(FluentIcons.test_beaker)));
    await tester.pumpAndSettle();

    expect(harness.provider.lastTestedActionId, 'action-1');

    await tester.tap(find.descendant(of: row, matching: find.byIcon(FluentIcons.more)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FluentIcons.delete).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, ptL10n.agentActionsDeleteConfirm));
    await tester.pumpAndSettle();

    expect(harness.repository.definitions, isNot(contains('action-1')));
  });

  testWidgets('Ctrl+N opens the action editor when the page has focus', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byType(ContentDialog), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormCreateTitle), findsOneWidget);
  });

  testWidgets('filters execution history by execution id search query', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    harness.repository.executions['execution-1'] = AgentActionExecution(
      id: 'execution-1',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime(2026, 5, 15, 8, 30),
      source: AgentActionRequestSource.localUi,
      traceId: 'trace-keep',
    );
    harness.repository.executions['execution-2'] = AgentActionExecution(
      id: 'execution-2',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.failed,
      requestedAt: DateTime(2026, 5, 15, 9, 30),
      source: AgentActionRequestSource.localUi,
      traceId: 'trace-other',
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openTab(tester, ptL10n.agentActionsHistoryTitle);

    harness.provider.setHistorySearchQuery('trace-keep');
    await tester.pumpAndSettle();

    expect(find.textContaining('trace-keep', findRichText: true), findsWidgets);
    expect(find.textContaining('trace-other', findRichText: true), findsNothing);
  });

  testWidgets('should filter execution history by failure phase in the UI', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    harness.repository.executions['exit-fail'] = AgentActionExecution(
      id: 'exit-fail',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.failed,
      requestedAt: DateTime(2026, 5, 15, 9),
      source: AgentActionRequestSource.localUi,
      failurePhase: 'process_exit',
    );
    harness.repository.executions['queue-fail'] = AgentActionExecution(
      id: 'queue-fail',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.failed,
      requestedAt: DateTime(2026, 5, 15, 8),
      source: AgentActionRequestSource.localUi,
      failurePhase: 'queue',
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openTab(tester, ptL10n.agentActionsHistoryTitle);

    harness.provider.setHistoryFailurePhaseFilter('process_exit');
    await tester.pumpAndSettle();

    expect(find.textContaining('exit-fail', findRichText: true), findsWidgets);
    expect(find.textContaining('queue-fail', findRichText: true), findsNothing);
  });

  testWidgets('shows secret placeholder info bar for command with secret reference', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Secret command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: r'echo ${secret:api_token}'),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openActionDetailsDialog(tester, 'action-1');

    expect(find.text(ptL10n.agentActionsSecretPlaceholdersTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsRiskSecretPlaceholders), findsWidgets);
    expect(find.textContaining('api_token', findRichText: true), findsWidgets);
  });

  testWidgets('shows secrets section with configure action when store is available', (tester) async {
    final harness = AgentActionsPageHarness(withActionSecretStore: true);
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Secret command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: r'echo ${secret:api_token}'),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openActionDetailsDialog(tester, 'action-1');

    expect(find.text(ptL10n.agentActionsSecretsSectionTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsSecretStatusMissing), findsOneWidget);
    expect(find.text(ptL10n.agentActionsSecretConfigure), findsOneWidget);
    expect(find.text(ptL10n.agentActionsMissingSecretsTitle), findsNothing);
  });

  testWidgets('should mark secret as configured after saving in configure dialog', (tester) async {
    final harness = AgentActionsPageHarness(withActionSecretStore: true);
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Secret command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: r'echo ${secret:api_token}'),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openActionDetailsDialog(tester, 'action-1');

    await tester.tap(
      find.byKey(const ValueKey<String>('agent_action_secret_configure_button_api_token')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ContentDialog), findsNWidgets(2));
    final dialog = find.ancestor(
      of: find.text(ptL10n.agentActionsSecretConfigureTitle('api_token')),
      matching: find.byType(ContentDialog),
    );
    expect(dialog, findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: dialog,
        matching: find.byType(TextBox),
      ),
      'configured-secret',
    );
    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.byKey(const ValueKey<String>('agent_action_secret_dialog_save_button')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('agent_action_secret_row_api_token')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('agent_action_secret_row_api_token')),
        matching: find.text(ptL10n.agentActionsSecretStatusConfigured),
      ),
      findsOneWidget,
    );
    expect(find.text(ptL10n.agentActionsSecretStatusMissing), findsNothing);
  });

  testWidgets('shows com object handlers missing warning when no handlers are registered', (tester) async {
    final harness = AgentActionsPageHarness(
      comObjectInvocationDiagnostics: const FakeComObjectInvocationDiagnostics(),
      includeComObjectRunner: true,
    );
    harness.repository.definitions['com-action'] = const AgentActionDefinition(
      id: 'com-action',
      name: 'COM action',
      state: AgentActionState.active,
      config: ComObjectActionConfig(
        progId: 'Data7.Application',
        memberName: 'Run',
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    expect(find.byKey(const ValueKey<String>('agent_actions_com_object_handlers_missing')), findsOneWidget);
    expect(find.text(ptL10n.agentActionsComObjectHandlersMissingMessage), findsOneWidget);
    await openTab(tester, ptL10n.configTabPreferences);
    expect(find.text(ptL10n.agentActionsSummaryComHandlersNone), findsOneWidget);
  });

  testWidgets('hides com object handlers warning when no com actions exist', (tester) async {
    final harness = AgentActionsPageHarness(
      comObjectInvocationDiagnostics: const FakeComObjectInvocationDiagnostics(),
      includeComObjectRunner: true,
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    expect(find.byKey(const ValueKey<String>('agent_actions_com_object_handlers_missing')), findsNothing);
    await openTab(tester, ptL10n.configTabPreferences);
    expect(find.text(ptL10n.agentActionsSummaryComHandlersNone), findsOneWidget);
  });

  testWidgets('shows com handlers count in summary when handlers are registered', (tester) async {
    final harness = AgentActionsPageHarness(
      comObjectInvocationDiagnostics: const FakeComObjectInvocationDiagnostics(registeredHandlerCount: 2),
      includeComObjectRunner: true,
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    expect(find.byKey(const ValueKey<String>('agent_actions_com_object_handlers_missing')), findsNothing);
    await openTab(tester, ptL10n.configTabPreferences);
    expect(find.text('2'), findsOneWidget);
    expect(find.text(ptL10n.agentActionsSummaryComHandlers), findsOneWidget);
  });

  testWidgets('shows scheduler instance lock warning when temporal scheduler did not start', (tester) async {
    final repository = FakeAgentActionRepository();
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Scheduled action',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    final runnerRegistry = AgentActionLocalRunnerRegistry([const FakeAgentActionLocalRunner()]);
    final runAction = RunAgentActionLocally(
      repository,
      runnerRegistry,
      const Uuid(),
      featureFlags: FeatureFlags(InMemoryAppSettingsStore()),
    );
    final scheduler = AgentActionTriggerScheduler(
      repository,
      DispatchAgentActionTrigger(repository, runAction),
      schedulerInstanceLock: const HeldSchedulerInstanceLockForPageTest(),
    );
    await scheduler.start();

    final harness = AgentActionsPageHarness(triggerScheduler: scheduler);

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    expect(find.byKey(const ValueKey<String>('agent_actions_scheduler_operational_issue')), findsOneWidget);
    expect(find.text(ptL10n.agentActionsSchedulerInstanceLockedMessage), findsOneWidget);
  });

  testWidgets('shows scheduler storage access denied warning when scheduler lock is inaccessible', (tester) async {
    final repository = FakeAgentActionRepository();
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Scheduled action',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    final runnerRegistry = AgentActionLocalRunnerRegistry([const FakeAgentActionLocalRunner()]);
    final runAction = RunAgentActionLocally(
      repository,
      runnerRegistry,
      const Uuid(),
      featureFlags: FeatureFlags(InMemoryAppSettingsStore()),
    );
    final scheduler = AgentActionTriggerScheduler(
      repository,
      DispatchAgentActionTrigger(repository, runAction),
      schedulerInstanceLock: const HeldSchedulerInstanceLockForPageTest(
        reason: AgentActionTriggerConstants.schedulerStorageAccessDeniedReason,
      ),
    );
    await scheduler.start();

    final harness = AgentActionsPageHarness(triggerScheduler: scheduler);

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await harness.pumpPage(tester);

    expect(find.byKey(const ValueKey<String>('agent_actions_scheduler_operational_issue')), findsOneWidget);
    expect(find.text(ptL10n.agentActionsSchedulerStorageAccessDeniedMessage), findsOneWidget);
  });

  testWidgets('should clear execution highlight when remote audit runtime instance mismatches', (tester) async {
    final auditStore = FakeRemoteAuditStore(
      records: <AgentActionRemoteAuditRecord>[
        AgentActionRemoteAuditRecord(
          id: 'audit-mismatch-ui',
          occurredAtUtc: DateTime.utc(2026, 5, 15, 11),
          rpcMethod: 'agent.action.run',
          outcome: 'success',
          credentialPresent: false,
          actionId: 'action-1',
          executionId: 'execution-1',
          runtimeInstanceId: 'inst-on-audit',
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
      runtimeInstanceId: 'inst-on-execution',
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openTab(tester, ptL10n.agentActionsRemoteAuditTitle);

    final showInHistory = find.text(ptL10n.agentActionsRemoteAuditShowInHistory);
    await tester.ensureVisible(showInHistory);
    expect(showInHistory, findsOneWidget);

    await tester.tap(showInHistory);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));

    expect(harness.provider.selectedActionId, 'action-1');
    expect(harness.provider.auditCorrelationExecutionId, isNull);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('shows remote risk chips and reapproval info bar for risky action', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Remote risky',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
      policies: AgentActionDefinitionPolicies(
        remote: AgentActionRemotePolicy(
          isEnabled: true,
          requiresReapproval: true,
        ),
        capture: AgentActionCapturePolicy(redactBeforePersisting: false),
        lifecycle: AgentActionLifecyclePolicy(
          onAppExit: AgentActionOnAppExitBehavior.leaveRunning,
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);

    expect(find.text(ptL10n.agentActionsRiskRemote), findsWidgets);
    expect(find.text(ptL10n.agentActionsRiskRemoteReapproval), findsWidgets);
    expect(find.text(ptL10n.agentActionsRiskSensitiveOutput), findsWidgets);
    expect(find.text(ptL10n.agentActionsRiskLeaveProcessRunning), findsWidgets);
    await openSelectedActionDialog(tester);
    expect(find.byKey(const ValueKey('agent_actions_remote_reapproval_info_bar')), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormRemoteReapprovalRequiredTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormRemoteReapprovalRequiredMessage), findsOneWidget);
  });

  testWidgets('should show capture policy controls for command line draft', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);

    await tester.ensureVisible(find.text(ptL10n.agentActionsFormCaptureStdout));

    expect(find.text(ptL10n.agentActionsFormCapturePolicyDescription), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormCaptureStdout), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormCaptureStderr), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormRedactBeforePersisting), findsOneWidget);
  });

  testWidgets('should load persisted capture policy into editor', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
      policies: AgentActionDefinitionPolicies(
        capture: AgentActionCapturePolicy(
          captureStdout: false,
          redactBeforePersisting: false,
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    await tester.ensureVisible(find.text(ptL10n.agentActionsFormCaptureStdout));

    final stdoutCheckbox = tester.widget<Checkbox>(
      find.ancestor(
        of: find.text(ptL10n.agentActionsFormCaptureStdout),
        matching: find.byType(Checkbox),
      ),
    );
    final stderrCheckbox = tester.widget<Checkbox>(
      find.ancestor(
        of: find.text(ptL10n.agentActionsFormCaptureStderr),
        matching: find.byType(Checkbox),
      ),
    );
    final redactCheckbox = tester.widget<Checkbox>(
      find.ancestor(
        of: find.text(ptL10n.agentActionsFormRedactBeforePersisting),
        matching: find.byType(Checkbox),
      ),
    );

    expect(stdoutCheckbox.checked, isFalse);
    expect(stderrCheckbox.checked, isTrue);
    expect(redactCheckbox.checked, isFalse);
  });

  testWidgets('should show queue and path allowlist controls for command line draft', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1600, 2400));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);

    await tester.ensureVisible(find.text(ptL10n.agentActionsFormMaxConcurrent));

    expect(find.text(ptL10n.agentActionsFormQueuePolicyDescription), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormMaxConcurrent), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormMaxQueued), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormConcurrencyBehavior), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormPathAllowlistDescription), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormAllowedWorkingDirectories), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormAllowedContextDirectories), findsOneWidget);
  });

  testWidgets('should surface definition_validation failure phase when test fails', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Invalid queue',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
      policies: AgentActionDefinitionPolicies(
        queue: AgentActionQueuePolicy(maxConcurrent: 0),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2400));
    await harness.pumpPage(tester);

    harness.provider.selectAction('action-1');
    await tester.pumpAndSettle();

    await tester.tap(find.text(ptL10n.agentActionsTestSelected));
    await tester.pumpAndSettle();
    await openActionDetailsDialog(tester, 'action-1');

    expect(find.byKey(const ValueKey('agent_actions_test_preview')), findsOneWidget);
    expect(
      find.textContaining(ptL10n.agentActionsFailurePhaseDefinitionValidation, findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('should load persisted queue and path policies into editor', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
      policies: AgentActionDefinitionPolicies(
        queue: AgentActionQueuePolicy(
          maxConcurrent: 2,
          maxQueued: 50,
          concurrencyBehavior: AgentActionConcurrencyBehavior.reject,
        ),
        path: AgentActionPathPolicy(
          allowedWorkingDirectories: {r'C:\jobs'},
          allowedContextDirectories: {r'C:\ctx'},
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2400));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    await tester.ensureVisible(find.text(ptL10n.agentActionsFormMaxConcurrent));

    expect(find.textContaining('2'), findsWidgets);
    expect(find.textContaining('50'), findsWidgets);
    expect(find.text(ptL10n.agentActionsFormConcurrencyReject), findsOneWidget);
    expect(find.textContaining(r'C:\jobs'), findsOneWidget);
    expect(find.textContaining(r'C:\ctx'), findsOneWidget);
  });

  testWidgets('shows stdout and stderr encoding controls for command line draft', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openCreateActionDialog(tester, ptL10n);

    final stdoutEncodingLabel = find.text(ptL10n.agentActionsFormStdoutEncoding);
    await tester.ensureVisible(stdoutEncodingLabel);

    expect(stdoutEncodingLabel, findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormStderrEncoding), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormOutputEncodingDescription), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormOutputEncodingSystemConsole), findsWidgets);
  });

  testWidgets('should load persisted encoding policy into editor', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
      policies: AgentActionDefinitionPolicies(
        encoding: AgentActionEncodingPolicy(
          stdout: AgentActionOutputEncodingMode.utf8,
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openSelectedActionDialog(tester);

    await tester.ensureVisible(find.text(ptL10n.agentActionsFormStdoutEncoding));

    expect(find.text(ptL10n.agentActionsFormOutputEncodingUtf8), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormOutputEncodingSystemConsole), findsOneWidget);
  });

  testWidgets('copies execution diagnostics support json to clipboard', (tester) async {
    String? clipboardPayload;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments as Map<dynamic, dynamic>;
          clipboardPayload = args['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    harness.repository.executions['execution-1'] = AgentActionExecution(
      id: 'execution-1',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.failed,
      requestedAt: DateTime(2026, 5, 15, 8, 30),
      source: AgentActionRequestSource.localUi,
      failureCode: AgentActionFailureCode.exitCodeRejected,
      failurePhase: 'process_exit',
      stdoutText: 'safe stdout',
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await harness.pumpPage(tester);
    await openTab(tester, ptL10n.agentActionsHistoryTitle);

    const copySupport = ValueKey<String>('execution_support_copy_button_execution-1');
    final copySupportFinder = find.byKey(copySupport);
    await tester.ensureVisible(copySupportFinder);
    await tester.tap(copySupportFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(clipboardPayload, isNotNull);
    final decoded = jsonDecode(clipboardPayload!) as Map<String, dynamic>;
    expect(decoded['execution_id'], 'execution-1');
    expect(decoded['stdout'], 'safe stdout');

    await tester.pump(const Duration(seconds: 4));
  });
}
