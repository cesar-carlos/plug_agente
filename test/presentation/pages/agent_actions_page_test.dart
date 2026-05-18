import 'dart:convert';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_secret_availability_checker.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_definitions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_triggers.dart';
import 'package:plug_agente/application/use_cases/list_developer_data7_connections.dart';
import 'package:plug_agente/application/use_cases/list_recent_agent_action_remote_audit.dart';
import 'package:plug_agente/application/use_cases/preview_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_trigger.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/runtime/windows_version_info.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_developer_data7_connection_gateway.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions_page.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

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
    final harness = _AgentActionsPageHarness();
    await harness.featureFlags.setEnableAgentActions(false);

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsDisabledTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormSave), findsNothing);
    expect(find.text(ptL10n.agentActionsFormCommand), findsNothing);
  });

  testWidgets('renders empty state and command line form', (tester) async {
    final harness = _AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.navAgentActions), findsWidgets);
    expect(find.text(ptL10n.agentActionsEmptyActions), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormCreateTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormName), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormCommand), findsOneWidget);
  });

  testWidgets('shows maintenance mode info bar when maintenance is enabled', (tester) async {
    final harness = _AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsMaintenanceModeInfoTitle), findsNothing);

    await harness.provider.setMaintenanceMode(enabled: true);
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsMaintenanceModeInfoTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsMaintenanceModeInfoMessage), findsOneWidget);
  });

  testWidgets('shows runtime support diagnostics card when desktop runtime is degraded', (tester) async {
    final harness = _AgentActionsPageHarness(
      runtimeCapabilities: RuntimeCapabilities.degraded(
        reasons: <String>[
          'Windows Server detectado',
          'Versão: 10.0.17763',
        ],
      ),
      runtimeDiagnostics: RuntimeDetectionDiagnostics.detected(
        source: RuntimeDetectionSource.rtlGetVersion,
        versionInfo: const WindowsVersionInfo(
          majorVersion: 10,
          minorVersion: 0,
          buildNumber: 17763,
          isServer: true,
          productName: 'Windows Server 2019',
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    expect(find.text('Runtime Detection'), findsOneWidget);
    expect(find.textContaining('runtime_mode: degraded', findRichText: true), findsWidgets);
    expect(find.textContaining('product_name: Windows Server 2019', findRichText: true), findsWidgets);
  });

  testWidgets('keeps actions page stable when resized to narrow width', (tester) async {
    final harness = _AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    await tester.binding.setSurfaceSize(const Size(920, 900));
    await tester.pumpAndSettle();

    expect(find.text('Run command'), findsWidgets);
    expect(find.byKey(const ValueKey<String>('agent_actions_detail_scroll')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps actions page stable in compact height viewport', (tester) async {
    final harness = _AgentActionsPageHarness();
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
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('agent_actions_detail_scroll')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders triggers section when triggers exist', (tester) async {
    final harness = _AgentActionsPageHarness();
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
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    await harness.provider.refreshTriggersForSelection();
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsTriggersTitle), findsOneWidget);
    expect(find.text('Morning'), findsOneWidget);
    expect(find.textContaining('America/Sao_Paulo'), findsOneWidget);
    expect(find.textContaining(ptL10n.agentActionsTriggerSummaryCatchUpEnabled), findsOneWidget);
  });

  testWidgets('saves a command line action from the form', (tester) async {
    final harness = _AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextBox).at(0), 'Run dir');
    await tester.enterText(find.byType(TextBox).at(2), 'dir');
    final saveAction = find.text(ptL10n.agentActionsFormSave);
    await tester.ensureVisible(saveAction);
    await tester.tap(saveAction);
    await tester.pumpAndSettle();

    expect(harness.repository.definitions, hasLength(1));
    expect(find.text('Run dir'), findsWidgets);
    expect(find.text(ptL10n.agentActionsFormEditTitle), findsOneWidget);
  });

  testWidgets('renders developer form for selected developer action', (tester) async {
    final harness = _AgentActionsPageHarness();
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
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

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
    final harness = _AgentActionsPageHarness();
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

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.text(ptL10n.agentActionsFormUseDefaultConfigBinPath),
    );
    await tester.tap(find.text(ptL10n.agentActionsFormUseDefaultConfigBinPath));
    await tester.pumpAndSettle();

    expect(find.text(r'C:\Data7\bin\Data7.Config'), findsWidgets);
    expect(
      find.text(ptL10n.agentActionsFormData7ConfigPathHintDefaultBin),
      findsOneWidget,
    );
  });

  testWidgets('shows developer binary path warnings for unexpected file names', (
    tester,
  ) async {
    final harness = _AgentActionsPageHarness();
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
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

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

    final harness = _AgentActionsPageHarness();
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
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

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
    final harness = _AgentActionsPageHarness();
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
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

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
    final harness = _AgentActionsPageHarness();
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
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.text(ptL10n.agentActionsTestSelected));
    await tester.pumpAndSettle();

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

  testWidgets('warns when saved developer connection changed', (tester) async {
    final harness = _AgentActionsPageHarness();
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
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

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
    final harness = _AgentActionsPageHarness();
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
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextBox).at(5),
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
    final harness = _AgentActionsPageHarness(
      developerConnectionGateway: _MissingDeveloperData7ConnectionGateway(),
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
    await tester.pumpWidget(harness.buildWidget());
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
    final harness = _AgentActionsPageHarness();
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
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

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
        '${ptL10n.agentActionsDiagnosticsFailurePhase}: Process Exit',
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
    await tester.pumpAndSettle();

    expect(
      harness.repository.executions['execution-1']?.status,
      AgentActionExecutionStatus.killed,
    );
    expect(find.text(ptL10n.agentActionsStatusKilled), findsOneWidget);
  });

  testWidgets('shows runner unavailable chip and info bar when subsystem is degraded', (tester) async {
    final guard = AgentActionRuntimeStateGuard()
      ..markDegraded(
        unavailableActionTypes: {AgentActionType.commandLine},
        reason: 'runner-missing',
      );
    final harness = _AgentActionsPageHarness(runtimeStateGuard: guard);
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Blocked command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsRiskRunnerUnavailable), findsWidgets);
    expect(find.text(ptL10n.agentActionsActionTypeUnavailableTitle), findsOneWidget);
    expect(find.textContaining('Linha de comando', findRichText: true), findsWidgets);
    expect(harness.provider.canRunSelected, isFalse);
  });

  testWidgets('filters execution history by execution id search query', (tester) async {
    final harness = _AgentActionsPageHarness();
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
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    harness.provider.setHistorySearchQuery('trace-keep');
    await tester.pumpAndSettle();

    expect(find.textContaining('trace-keep', findRichText: true), findsWidgets);
    expect(find.textContaining('trace-other', findRichText: true), findsNothing);
  });

  testWidgets('shows secret placeholder info bar for command with secret reference', (tester) async {
    final harness = _AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Secret command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: r'echo ${secret:api_token}'),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsSecretPlaceholdersTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsRiskSecretPlaceholders), findsWidgets);
    expect(find.textContaining('api_token', findRichText: true), findsWidgets);
  });

  testWidgets('shows secrets section with configure action when store is available', (tester) async {
    final harness = _AgentActionsPageHarness(withActionSecretStore: true);
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Secret command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: r'echo ${secret:api_token}'),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsSecretsSectionTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsSecretStatusMissing), findsOneWidget);
    expect(find.text(ptL10n.agentActionsSecretConfigure), findsOneWidget);
    expect(find.text(ptL10n.agentActionsMissingSecretsTitle), findsNothing);
  });

  testWidgets('should mark secret as configured after saving in configure dialog', (tester) async {
    final harness = _AgentActionsPageHarness(withActionSecretStore: true);
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Secret command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: r'echo ${secret:api_token}'),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('agent_action_secret_configure_button_api_token')),
    );
    await tester.pumpAndSettle();

    final dialog = find.byType(ContentDialog);
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

  testWidgets('shows remote risk chips and reapproval info bar for risky action', (tester) async {
    final harness = _AgentActionsPageHarness();
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
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsRiskRemote), findsWidgets);
    expect(find.text(ptL10n.agentActionsRiskRemoteReapproval), findsWidgets);
    expect(find.text(ptL10n.agentActionsRiskSensitiveOutput), findsWidgets);
    expect(find.text(ptL10n.agentActionsRiskLeaveProcessRunning), findsWidgets);
    expect(find.byKey(const ValueKey('agent_actions_remote_reapproval_info_bar')), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormRemoteReapprovalRequiredTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsFormRemoteReapprovalRequiredMessage), findsOneWidget);
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

    final harness = _AgentActionsPageHarness();
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
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

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

class _AgentActionsPageHarness {
  _AgentActionsPageHarness({
    IDeveloperData7ConnectionGateway? developerConnectionGateway,
    AgentActionRuntimeStateGuard? runtimeStateGuard,
    RuntimeCapabilities? runtimeCapabilities,
    RuntimeDetectionDiagnostics? runtimeDiagnostics,
    bool withActionSecretStore = false,
  }) : _developerConnectionGateway = developerConnectionGateway ?? _FakeDeveloperData7ConnectionGateway(),
       _runtimeStateGuard = runtimeStateGuard,
       _runtimeCapabilities = runtimeCapabilities ?? RuntimeCapabilities.full(),
       _runtimeDiagnostics = runtimeDiagnostics,
       _actionSecretStore = withActionSecretStore ? _HarnessAgentActionSecretStore() : null {
    final validateDefinition = ValidateAgentActionDefinition(
      AgentActionAdapterRegistry([
        const _FakeCommandLineActionAdapter(),
        const _FakeDeveloperActionAdapter(),
      ]),
    );
    final previewDefinition = PreviewAgentActionDefinition(
      repository,
      AgentActionAdapterRegistry([
        const _FakeCommandLineActionAdapter(),
        const _FakeDeveloperActionAdapter(),
      ]),
    );
    final runnerRegistry = AgentActionLocalRunnerRegistry([
      const _FakeAgentActionLocalRunner(),
      const _FakeDeveloperActionLocalRunner(),
    ]);

    provider = AgentActionsProvider(
      ListAgentActionDefinitions(repository),
      ListAgentActionExecutions(repository),
      SaveAgentActionDefinition(
        repository,
        validateDefinition,
        const AgentActionDefinitionSnapshotter(),
      ),
      DeleteAgentActionDefinition(repository),
      ListAgentActionTriggers(repository),
      DeleteAgentActionTrigger(repository),
      SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
      ),
      ListDeveloperData7Connections(_developerConnectionGateway),
      RunAgentActionLocally(
        repository,
        runnerRegistry,
        const Uuid(),
        executionQueue: executionQueue,
        featureFlags: featureFlags,
      ),
      TestAgentActionDefinition(repository, validateDefinition),
      previewDefinition,
      CancelAgentActionExecution(
        repository,
        runnerRegistry,
        executionQueue: executionQueue,
      ),
      GetAgentActionExecution(repository),
      ListRecentAgentActionRemoteAudit(_StubRemoteAuditStore()),
      featureFlags,
      const Uuid(),
      runtimeStateGuard: _runtimeStateGuard,
      executionQueue: executionQueue,
      secretAvailabilityChecker: _actionSecretStore == null
          ? null
          : AgentActionSecretAvailabilityChecker(secretStore: _actionSecretStore),
      saveAgentActionSecret: _actionSecretStore == null ? null : SaveAgentActionSecret(_actionSecretStore),
      deleteAgentActionSecret: _actionSecretStore == null ? null : DeleteAgentActionSecret(_actionSecretStore),
      now: () => DateTime(2026, 5, 15, 12),
    );
  }

  final _HarnessAgentActionSecretStore? _actionSecretStore;
  final _FakeAgentActionRepository repository = _FakeAgentActionRepository();
  final FeatureFlags featureFlags = FeatureFlags(InMemoryAppSettingsStore());
  final ActionExecutionQueue executionQueue = ActionExecutionQueue();
  final IDeveloperData7ConnectionGateway _developerConnectionGateway;
  final AgentActionRuntimeStateGuard? _runtimeStateGuard;
  final RuntimeCapabilities _runtimeCapabilities;
  final RuntimeDetectionDiagnostics? _runtimeDiagnostics;
  late final AgentActionsProvider provider;

  Widget buildWidget() {
    if (getIt.isRegistered<RuntimeCapabilities>()) {
      getIt.unregister<RuntimeCapabilities>();
    }
    getIt.registerSingleton<RuntimeCapabilities>(_runtimeCapabilities);
    if (getIt.isRegistered<RuntimeDetectionDiagnostics>()) {
      getIt.unregister<RuntimeDetectionDiagnostics>();
    }
    if (_runtimeDiagnostics != null) {
      getIt.registerSingleton<RuntimeDetectionDiagnostics>(_runtimeDiagnostics);
    }

    return FluentApp(
      locale: const Locale('pt'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<AgentActionsProvider>.value(
        value: provider,
        child: const AgentActionsPage(),
      ),
    );
  }
}

class _FakeCommandLineActionAdapter implements AgentActionAdapter {
  const _FakeCommandLineActionAdapter();

  @override
  AgentActionType get type => AgentActionType.commandLine;

  @override
  Future<Result<AgentActionPreflight>> validateDefinition(
    AgentActionDefinition definition,
  ) async {
    return Success(
      AgentActionPreflight(
        actionType: type,
        canRun: definition.canRun,
      ),
    );
  }

  @override
  Future<Result<AgentActionPreparedExecution>> prepareExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    return Success(
      AgentActionPreparedExecution(
        actionType: type,
        redactedCommandPreview: 'cmd.exe /C ***',
      ),
    );
  }

  @override
  Future<Result<AgentActionDefinition>> normalizeDefinition(
    AgentActionDefinition definition,
  ) async {
    return Success(definition);
  }
}

class _FakeDeveloperActionAdapter implements AgentActionAdapter {
  const _FakeDeveloperActionAdapter();

  @override
  AgentActionType get type => AgentActionType.developer;

  @override
  Future<Result<AgentActionPreflight>> validateDefinition(
    AgentActionDefinition definition,
  ) async {
    return Success(
      AgentActionPreflight(
        actionType: type,
        canRun: definition.canRun,
      ),
    );
  }

  @override
  Future<Result<AgentActionPreparedExecution>> prepareExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    return Success(
      AgentActionPreparedExecution(
        actionType: type,
        redactedCommandPreview: r'C:\Data7\bin\Executor.exe -p *** -c ***',
        redactedDiagnostics: const {
          'engine': 'data7Executor',
          'connection_label': 'Estacao',
          'catalog_connection_count': 1,
          'used_default_config_path': false,
        },
      ),
    );
  }

  @override
  Future<Result<AgentActionDefinition>> normalizeDefinition(
    AgentActionDefinition definition,
  ) async {
    return Success(definition);
  }
}

class _FakeAgentActionLocalRunner implements AgentActionLocalRunner {
  const _FakeAgentActionLocalRunner();

  @override
  AgentActionType get type => AgentActionType.commandLine;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    return Success(
      AgentActionProcessResult(
        status: AgentActionExecutionStatus.succeeded,
        pid: 1234,
        exitCode: 0,
        processStartedAt: DateTime(2026, 5, 15, 9),
        finishedAt: DateTime(2026, 5, 15, 9, 1),
        stdout: const AgentActionCapturedOutput(
          text: 'safe stdout',
          isCaptured: true,
        ),
        stderr: AgentActionCapturedOutput.disabled,
        redactionApplied: true,
      ),
    );
  }

  @override
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
  }) async {
    return Success(
      AgentActionCancellationResult(
        executionId: executionId,
        status: AgentActionExecutionStatus.killed,
        killed: true,
        pid: 1234,
        message: 'Processo principal finalizado.',
      ),
    );
  }
}

class _FakeDeveloperActionLocalRunner implements AgentActionLocalRunner {
  const _FakeDeveloperActionLocalRunner();

  @override
  AgentActionType get type => AgentActionType.developer;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    return Success(
      AgentActionProcessResult(
        status: AgentActionExecutionStatus.succeeded,
        pid: 5678,
        exitCode: 0,
        processStartedAt: DateTime(2026, 5, 15, 9),
        finishedAt: DateTime(2026, 5, 15, 9, 1),
        stdout: const AgentActionCapturedOutput(
          text: 'safe stdout',
          isCaptured: true,
        ),
        stderr: AgentActionCapturedOutput.disabled,
        redactionApplied: true,
      ),
    );
  }

  @override
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
  }) async {
    return Success(
      AgentActionCancellationResult(
        executionId: executionId,
        status: AgentActionExecutionStatus.killed,
        killed: true,
        pid: 5678,
        message: 'Processo principal finalizado.',
      ),
    );
  }
}

class _FakeDeveloperData7ConnectionGateway implements IDeveloperData7ConnectionGateway {
  @override
  Future<Result<DeveloperData7ConnectionLookupResult>> listConnections(
    DeveloperData7ConnectionLookupRequest request,
  ) async {
    return Success(
      DeveloperData7ConnectionLookupResult(
        resolvedConfigPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Data7.Config',
          canonicalPath: r'C:\Data7\bin\Data7.Config',
          existsAtValidation: true,
        ),
        usedDefaultLocation: false,
        selectedConnectionId: request.selectedConnectionId,
        connections: const [
          DeveloperData7ConnectionOption(
            id: '34512A51-672C-4ECE-9991-F43E175E7A8B',
            label: 'Estacao',
            snapshotHash: 'hash-estacao',
          ),
        ],
      ),
    );
  }
}

class _MissingDeveloperData7ConnectionGateway implements IDeveloperData7ConnectionGateway {
  @override
  Future<Result<DeveloperData7ConnectionLookupResult>> listConnections(
    DeveloperData7ConnectionLookupRequest request,
  ) async {
    return Success(
      DeveloperData7ConnectionLookupResult(
        resolvedConfigPath: const AgentActionPathReference(
          originalPath: r'C:\Data7\bin\Data7.Config',
          canonicalPath: r'C:\Data7\bin\Data7.Config',
          existsAtValidation: true,
        ),
        usedDefaultLocation: false,
        selectedConnectionId: request.selectedConnectionId,
        connections: const [
          DeveloperData7ConnectionOption(
            id: '1DA725C7-129C-4D53-84A1-CA55B80057E6',
            label: 'Campo',
            snapshotHash: 'hash-campo',
          ),
        ],
      ),
    );
  }
}

class _FakeAgentActionRepository implements IAgentActionRepository {
  final Map<String, AgentActionDefinition> definitions = {};
  final Map<String, AgentActionTrigger> triggers = {};
  final Map<String, AgentActionExecution> executions = {};

  @override
  Future<Result<AgentActionDefinition>> saveDefinition(
    AgentActionDefinition definition,
  ) async {
    definitions[definition.id] = definition;
    return Success(definition);
  }

  @override
  Future<Result<AgentActionDefinition>> getDefinition(String id) async {
    final definition = definitions[id];
    if (definition == null) {
      return Failure(
        ActionNotFoundFailure.withContext(
          message: 'Action definition was not found.',
          context: {'action_id': id, 'reason': AgentActionRpcConstants.agentActionExecutionNotFoundContextReason},
        ),
      );
    }

    return Success(definition);
  }

  @override
  Future<Result<List<AgentActionDefinition>>> listDefinitions() async {
    return Success(definitions.values.toList(growable: false));
  }

  @override
  Future<Result<void>> deleteDefinition(String id) async {
    definitions.remove(id);
    triggers.removeWhere((_, AgentActionTrigger trigger) => trigger.actionId == id);
    return const Success(unit);
  }

  @override
  Future<Result<AgentActionTrigger>> saveTrigger(
    AgentActionTrigger trigger,
  ) async {
    triggers[trigger.id] = trigger;
    return Success(trigger);
  }

  @override
  Future<Result<AgentActionTrigger>> getTrigger(String id) async {
    final trigger = triggers[id];
    if (trigger == null) {
      return Failure(
        ActionNotFoundFailure.withContext(
          message: 'Action trigger was not found.',
          context: {'trigger_id': id, 'reason': AgentActionRpcConstants.agentActionExecutionNotFoundContextReason},
        ),
      );
    }

    return Success(trigger);
  }

  @override
  Future<Result<List<AgentActionTrigger>>> listTriggers({
    String? actionId,
    bool? isEnabled,
    Set<AgentActionTriggerType>? types,
  }) async {
    final filtered = triggers.values
        .where((trigger) {
          final matchesAction = actionId == null || trigger.actionId == actionId;
          final matchesEnabled = isEnabled == null || trigger.isEnabled == isEnabled;
          final matchesType = types == null || types.isEmpty || types.contains(trigger.type);
          return matchesAction && matchesEnabled && matchesType;
        })
        .toList(growable: false);

    return Success(filtered);
  }

  @override
  Future<Result<void>> deleteTrigger(String id) async {
    triggers.remove(id);
    return const Success(unit);
  }

  @override
  Future<Result<AgentActionExecution>> saveExecution(
    AgentActionExecution execution,
  ) async {
    executions[execution.id] = execution;
    return Success(execution);
  }

  @override
  Future<Result<AgentActionExecution>> getExecution(String id) async {
    final execution = executions[id];
    if (execution == null) {
      return Failure(
        ActionNotFoundFailure.withContext(
          message: 'Action execution was not found.',
          context: {'execution_id': id, 'reason': AgentActionRpcConstants.agentActionExecutionNotFoundContextReason},
        ),
      );
    }

    return Success(execution);
  }

  @override
  Future<Result<List<AgentActionExecution>>> listExecutions({
    String? actionId,
    String? idempotencyKey,
    Set<AgentActionExecutionStatus>? statuses,
    DateTime? requestedAfter,
    int? limit,
  }) async {
    final filtered = executions.values
        .where((execution) {
          final matchesAction = actionId == null || execution.actionId == actionId;
          final matchesIdempotencyKey = idempotencyKey == null || execution.idempotencyKey == idempotencyKey;
          final matchesStatus = statuses == null || statuses.isEmpty || statuses.contains(execution.status);
          final matchesRequestedAfter = requestedAfter == null || !execution.requestedAt.isBefore(requestedAfter);
          return matchesAction && matchesIdempotencyKey && matchesStatus && matchesRequestedAfter;
        })
        .toList(growable: false);

    return Success(
      limit == null ? filtered : filtered.take(limit).toList(growable: false),
    );
  }

  @override
  Future<Result<int>> cleanupExecutions({
    required DateTime olderThan,
  }) async {
    final before = executions.length;
    executions.removeWhere((_, execution) {
      final finishedAt = execution.finishedAt;
      return finishedAt != null && finishedAt.isBefore(olderThan);
    });

    return Success(before - executions.length);
  }
}

class _StubRemoteAuditStore implements IAgentActionRemoteAuditStore {
  @override
  Future<void> append(AgentActionRemoteAuditRecord record) async {}

  @override
  Future<List<AgentActionRemoteAuditRecord>> listRecent({int limit = 200}) async =>
      const <AgentActionRemoteAuditRecord>[];

  @override
  Future<int> deleteWhereOccurredBefore({
    required DateTime cutoffUtc,
    required int limit,
  }) async => 0;
}

class _HarnessAgentActionSecretStore implements IAgentActionSecretStore {
  final Map<String, String> _values = <String, String>{};

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecret(String secretName) async {
    _values.remove(secretName);
  }

  @override
  Future<bool> exists(String secretName) async {
    final value = await readSecret(secretName);
    return value != null && value.isNotEmpty;
  }

  @override
  Future<String?> readSecret(String secretName) async => _values[secretName];

  @override
  Future<void> saveSecret(String secretName, String secretValue) async {
    _values[secretName] = secretValue;
  }
}
