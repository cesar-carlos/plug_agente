import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_backup_sanitizer.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/rpc/agent_action_execution_output_pager.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/dispatch_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/export_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/import_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_definitions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_triggers.dart';
import 'package:plug_agente/application/use_cases/list_developer_data7_connections.dart';
import 'package:plug_agente/application/use_cases/list_recent_agent_action_remote_audit.dart';
import 'package:plug_agente/application/use_cases/preview_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/slice_agent_action_captured_output.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_trigger.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_captured_output_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_scheduler_instance_lock.dart';
import 'package:plug_agente/domain/repositories/i_com_object_invocation_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_developer_data7_connection_gateway.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_portable_codec.dart';
import 'package:plug_agente/presentation/providers/agent_action_remote_audit_focus_result.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

void main() {
  late _FakeAgentActionRepository repository;
  late FeatureFlags featureFlags;
  late ActionExecutionQueue executionQueue;
  late AgentActionsProvider provider;
  late _FakeDeveloperData7ConnectionGateway developerData7ConnectionGateway;

  setUp(() {
    repository = _FakeAgentActionRepository();
    featureFlags = FeatureFlags(InMemoryAppSettingsStore());
    executionQueue = ActionExecutionQueue();
    developerData7ConnectionGateway = _FakeDeveloperData7ConnectionGateway();

    final runnerRegistry = AgentActionLocalRunnerRegistry([
      const _FakeAgentActionLocalRunner(),
      const _FakeDeveloperActionLocalRunner(),
    ]);
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
    final saveDefinition = SaveAgentActionDefinition(
      repository,
      validateDefinition,
      const AgentActionDefinitionSnapshotter(),
      featureFlags,
    );
    const portableCodec = AgentActionPortableCodec();
    final backupSanitizer = AgentActionBackupSanitizer(codec: portableCodec);

    provider = AgentActionsProvider(
      ListAgentActionDefinitions(repository),
      ListAgentActionExecutions(repository),
      saveDefinition,
      DeleteAgentActionDefinition(repository),
      ListAgentActionTriggers(repository),
      DeleteAgentActionTrigger(repository),
      SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      ),
      ListDeveloperData7Connections(developerData7ConnectionGateway),
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
      SliceAgentActionCapturedOutput(repository),
      ListRecentAgentActionRemoteAudit(_StubRemoteAuditStore()),
      ExportAgentActionsBundle(
        ListAgentActionDefinitions(repository),
        ListAgentActionTriggers(repository),
        backupSanitizer,
      ),
      ImportAgentActionsBundle(
        saveDefinition,
        SaveAgentActionTrigger(
          repository,
          const ValidateAgentActionTrigger(),
          featureFlags,
        ),
        backupSanitizer,
      ),
      featureFlags,
      const Uuid(),
      now: () => DateTime(2026, 5, 15, 12),
    );
  });

  test('tests selected action without creating execution history', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await provider.load();
    await provider.testSelectedAction();

    expect(provider.errorMessage, isNull);
    expect(provider.lastTestedActionId, 'action-1');
    expect(provider.lastTestCanRun, isTrue);
    expect(provider.lastTestCommandPreview, 'cmd.exe /C ***');
    expect(provider.lastTestPreviewErrorMessage, isNull);
    expect(provider.isTesting, isFalse);
    expect(repository.savedExecutions, isEmpty);
  });

  test('loads triggers for the selected action after refresh', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.triggers['trig-1'] = const AgentActionTrigger(
      id: 'trig-1',
      actionId: 'action-1',
      type: AgentActionTriggerType.daily,
      name: 'Morning',
    );

    await provider.load();
    await provider.refreshTriggersForSelection();

    expect(provider.isLoadingTriggers, isFalse);
    expect(provider.triggers, hasLength(1));
    expect(provider.triggers.single.id, 'trig-1');
  });

  test('deletes trigger for selected action', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.triggers['trig-1'] = const AgentActionTrigger(
      id: 'trig-1',
      actionId: 'action-1',
      type: AgentActionTriggerType.daily,
      name: 'Morning',
    );

    await provider.load();
    await provider.refreshTriggersForSelection();
    await provider.deleteTrigger('trig-1');

    expect(repository.triggers, isEmpty);
    expect(provider.triggers, isEmpty);
    expect(provider.errorMessage, isNull);
  });

  test('saves manual trigger through save use case', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await provider.load();
    await provider.refreshTriggersForSelection();

    final ok = await provider.saveTrigger(
      const AgentActionTrigger(
        id: 'trig-new',
        actionId: 'action-1',
        type: AgentActionTriggerType.manual,
      ),
    );

    expect(ok, isTrue);
    expect(provider.errorMessage, isNull);
    expect(repository.triggers['trig-new'], isNotNull);
  });

  test('saves temporal trigger with ignoreMissedRuns false', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await provider.load();
    await provider.refreshTriggersForSelection();

    final ok = await provider.saveTrigger(
      const AgentActionTrigger(
        id: 'trig-catch-up',
        actionId: 'action-1',
        type: AgentActionTriggerType.daily,
        name: 'Night',
        schedule: AgentActionTriggerSchedule(
          timeOfDayMinutes: 22 * 60,
          ignoreMissedRuns: false,
        ),
      ),
    );

    expect(ok, isTrue);
    expect(repository.triggers['trig-catch-up']?.schedule.ignoreMissedRuns, isFalse);
  });

  test('save trigger returns false when validation fails', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await provider.load();

    final ok = await provider.saveTrigger(
      const AgentActionTrigger(
        id: 'trig-bad',
        actionId: 'action-1',
        type: AgentActionTriggerType.once,
      ),
    );

    expect(ok, isFalse);
    expect(provider.errorMessage, isNotEmpty);
  });

  test('saves command line action through validated use case', () async {
    await provider.saveCommandLineAction(
      name: 'Run dir',
      command: 'dir',
      state: AgentActionState.active,
    );

    expect(provider.errorMessage, isNull);
    expect(provider.definitions, hasLength(1));
    expect(provider.selectedDefinition?.name, 'Run dir');
    expect(provider.selectedDefinition?.config, isA<CommandLineActionConfig>());
    expect(provider.isSaving, isFalse);
  });

  test('should persist encoding policy when saving command line action', () async {
    await provider.saveCommandLineAction(
      name: 'Run dir',
      command: 'dir',
      encodingPolicy: const AgentActionEncodingPolicy(
        stdout: AgentActionOutputEncodingMode.utf8,
      ),
    );

    expect(provider.errorMessage, isNull);
    expect(provider.selectedDefinition?.policies.encoding.stdout, AgentActionOutputEncodingMode.utf8);
    expect(
      provider.selectedDefinition?.policies.encoding.stderr,
      AgentActionOutputEncodingMode.systemConsole,
    );
  });

  test('saves developer action through validated use case', () async {
    await provider.saveDeveloperData7Action(
      name: 'Transmitir Data7',
      executorPath: r'C:\Data7\bin\Executor.exe',
      projectPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
      data7ConfigPath: r'C:\Data7\bin\Data7.Config',
      connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
      connectionLabel: 'Estacao',
      state: AgentActionState.active,
    );

    expect(provider.errorMessage, isNull);
    expect(provider.definitions, hasLength(1));
    expect(provider.selectedDefinition?.name, 'Transmitir Data7');
    final config = provider.selectedDefinition?.config;
    expect(config, isA<DeveloperActionConfig>());
    final developerConfig = config! as DeveloperActionConfig;
    expect(developerConfig.executorPath.originalPath, r'C:\Data7\bin\Executor.exe');
    expect(developerConfig.projectPath.originalPath, r'C:\Data7\Transmissao\Transmissor.7Proj');
    expect(developerConfig.connectionId, '34512A51-672C-4ECE-9991-F43E175E7A8B');
    expect(developerConfig.connectionLabel, 'Estacao');
    expect(provider.isSaving, isFalse);
  });

  test('should persist encoding policy when saving developer action', () async {
    await provider.saveDeveloperData7Action(
      name: 'Transmitir Data7',
      executorPath: r'C:\Data7\bin\Executor.exe',
      projectPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
      data7ConfigPath: r'C:\Data7\bin\Data7.Config',
      connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
      connectionLabel: 'Estacao',
      encodingPolicy: const AgentActionEncodingPolicy(
        stdout: AgentActionOutputEncodingMode.utf8,
        stderr: AgentActionOutputEncodingMode.utf8,
      ),
    );

    expect(provider.errorMessage, isNull);
    expect(provider.selectedDefinition?.policies.encoding.stdout, AgentActionOutputEncodingMode.utf8);
    expect(provider.selectedDefinition?.policies.encoding.stderr, AgentActionOutputEncodingMode.utf8);
  });

  test('loads developer Data7 connections and resolves safe metadata', () async {
    await provider.loadDeveloperData7Connections(
      actionId: 'developer-draft',
      data7ConfigPath: r'C:\Data7\bin\Data7.Config',
      selectedConnectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
    );

    expect(provider.isLoadingDeveloperConnections, isFalse);
    expect(provider.developerConnectionLookupMessage, isNull);
    expect(provider.resolvedDeveloperData7ConfigPath, r'C:\Data7\bin\Data7.Config');
    expect(provider.usedDefaultDeveloperData7ConfigPath, isFalse);
    expect(provider.developerConnections, hasLength(2));
    expect(provider.developerConnections.first.label, 'Estacao');
  });

  test('stores redacted preview diagnostics for developer test', () async {
    repository.definitions['action-1'] = AgentActionDefinition(
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

    await provider.load();
    await provider.testSelectedAction();

    expect(
      provider.lastTestCommandPreview,
      r'C:\Data7\bin\Executor.exe -p *** -c ***',
    );
    expect(provider.lastTestDiagnostics['connection_label'], 'Estacao');
    expect(provider.lastTestDiagnostics['engine'], 'data7Executor');
  });

  test('deletes selected action when no execution is active', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );

    await provider.load();

    expect(provider.canDeleteSelected, isTrue);

    await provider.deleteSelectedAction();

    expect(provider.errorMessage, isNull);
    expect(provider.definitions, isEmpty);
    expect(provider.selectedDefinition, isNull);
    expect(provider.isDeleting, isFalse);
  });

  test('does not delete selected action when visible execution is active', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.executions['execution-1'] = AgentActionExecution(
      id: 'execution-1',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.running,
      requestedAt: DateTime(2026, 5, 15, 9),
      source: AgentActionRequestSource.localUi,
    );

    await provider.load();

    expect(provider.canDeleteSelected, isFalse);

    await provider.deleteSelectedAction();

    expect(provider.definitions, hasLength(1));
    expect(repository.definitions, contains('action-1'));
  });

  test('should expose scheduler instance locked reason when temporal scheduler did not start', () async {
    final schedulerLock = _ProviderTestHeldSchedulerLock();
    final runnerRegistry = AgentActionLocalRunnerRegistry([const _FakeAgentActionLocalRunner()]);
    final validateDefinition = ValidateAgentActionDefinition(
      AgentActionAdapterRegistry([const _FakeCommandLineActionAdapter()]),
    );
    final saveDefinition = SaveAgentActionDefinition(
      repository,
      validateDefinition,
      const AgentActionDefinitionSnapshotter(),
      featureFlags,
    );
    final dispatchTrigger = DispatchAgentActionTrigger(
      repository,
      RunAgentActionLocally(
        repository,
        runnerRegistry,
        const Uuid(),
        executionQueue: executionQueue,
        featureFlags: featureFlags,
      ),
    );
    final scheduler = AgentActionTriggerScheduler(
      repository,
      dispatchTrigger,
      schedulerInstanceLock: schedulerLock,
    );
    await scheduler.start();

    const portableCodec = AgentActionPortableCodec();
    final backupSanitizer = AgentActionBackupSanitizer(codec: portableCodec);

    final providerWithScheduler = AgentActionsProvider(
      ListAgentActionDefinitions(repository),
      ListAgentActionExecutions(repository),
      saveDefinition,
      DeleteAgentActionDefinition(repository),
      ListAgentActionTriggers(repository),
      DeleteAgentActionTrigger(repository),
      SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      ),
      ListDeveloperData7Connections(developerData7ConnectionGateway),
      RunAgentActionLocally(
        repository,
        runnerRegistry,
        const Uuid(),
        executionQueue: executionQueue,
        featureFlags: featureFlags,
      ),
      TestAgentActionDefinition(repository, validateDefinition),
      PreviewAgentActionDefinition(
        repository,
        AgentActionAdapterRegistry([const _FakeCommandLineActionAdapter()]),
      ),
      CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([const _FakeAgentActionLocalRunner()]),
        executionQueue: executionQueue,
      ),
      GetAgentActionExecution(repository),
      SliceAgentActionCapturedOutput(repository),
      ListRecentAgentActionRemoteAudit(_StubRemoteAuditStore()),
      ExportAgentActionsBundle(
        ListAgentActionDefinitions(repository),
        ListAgentActionTriggers(repository),
        backupSanitizer,
      ),
      ImportAgentActionsBundle(
        saveDefinition,
        SaveAgentActionTrigger(
          repository,
          const ValidateAgentActionTrigger(),
          featureFlags,
        ),
        backupSanitizer,
      ),
      featureFlags,
      const Uuid(),
      triggerScheduler: scheduler,
    );

    expect(
      providerWithScheduler.schedulerOperationalIssueReason,
      AgentActionTriggerConstants.schedulerInstanceLockedReason,
    );
  });

  test('should warn when com object runner is registered but no handlers are configured', () {
    final runnerRegistry = AgentActionLocalRunnerRegistry([
      const _FakeAgentActionLocalRunner(),
      const _FakeComObjectLocalRunner(),
    ]);
    final providerWithCom = _buildProvider(
      repository: repository,
      featureFlags: featureFlags,
      executionQueue: executionQueue,
      developerData7ConnectionGateway: developerData7ConnectionGateway,
      runnerRegistry: runnerRegistry,
      comObjectInvocationDiagnostics: const _FakeComObjectInvocationDiagnostics(),
    );

    expect(providerWithCom.shouldWarnComObjectHandlersMissing, isTrue);
  });

  test('should not warn com object handlers when registry has handlers', () {
    final runnerRegistry = AgentActionLocalRunnerRegistry([
      const _FakeAgentActionLocalRunner(),
      const _FakeComObjectLocalRunner(),
    ]);
    final providerWithCom = _buildProvider(
      repository: repository,
      featureFlags: featureFlags,
      executionQueue: executionQueue,
      developerData7ConnectionGateway: developerData7ConnectionGateway,
      runnerRegistry: runnerRegistry,
      comObjectInvocationDiagnostics: const _FakeComObjectInvocationDiagnostics(
        registeredHandlerCount: 1,
      ),
    );

    expect(providerWithCom.shouldWarnComObjectHandlersMissing, isFalse);
  });

  test('should expose com object handlers count when diagnostics are wired', () {
    final runnerRegistry = AgentActionLocalRunnerRegistry([
      const _FakeAgentActionLocalRunner(),
      const _FakeComObjectLocalRunner(),
    ]);
    final providerWithCom = _buildProvider(
      repository: repository,
      featureFlags: featureFlags,
      executionQueue: executionQueue,
      developerData7ConnectionGateway: developerData7ConnectionGateway,
      runnerRegistry: runnerRegistry,
      comObjectInvocationDiagnostics: const _FakeComObjectInvocationDiagnostics(
        registeredHandlerCount: 2,
      ),
    );

    expect(providerWithCom.comObjectHandlersRegisteredCount, 2);
  });

  test('should return null com object handlers count when diagnostics are omitted', () {
    final providerWithoutDiagnostics = _buildProvider(
      repository: repository,
      featureFlags: featureFlags,
      executionQueue: executionQueue,
      developerData7ConnectionGateway: developerData7ConnectionGateway,
    );

    expect(providerWithoutDiagnostics.comObjectHandlersRegisteredCount, isNull);
  });

  test('focusExecutionFromRemoteAudit selects action and highlights execution', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.definitions['action-2'] = const AgentActionDefinition(
      id: 'action-2',
      name: 'Other',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.executions['execution-1'] = AgentActionExecution(
      id: 'execution-1',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime(2026, 5, 15, 9),
      source: AgentActionRequestSource.remoteHub,
      finishedAt: DateTime(2026, 5, 15, 10),
      redactionApplied: true,
    );

    await provider.load();

    final record = AgentActionRemoteAuditRecord(
      id: 'audit-row',
      occurredAtUtc: DateTime.utc(2026, 5, 15, 11),
      rpcMethod: 'agent.action.run',
      outcome: 'success',
      credentialPresent: false,
      actionId: 'action-1',
      executionId: 'execution-1',
    );
    final result = await provider.focusExecutionFromRemoteAudit(record);

    expect(result, AgentActionRemoteAuditFocusResult.succeeded);
    expect(provider.selectedActionId, 'action-1');
    expect(provider.auditCorrelationExecutionId, 'execution-1');

    provider.selectAction('action-2');
    expect(provider.auditCorrelationExecutionId, isNull);
  });

  test('focusExecutionFromRemoteAudit fetches execution outside list window', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.executions['old-exec'] = AgentActionExecution(
      id: 'old-exec',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime(2020),
      source: AgentActionRequestSource.remoteHub,
      finishedAt: DateTime(2020, 1, 1, 1),
      redactionApplied: true,
    );

    await provider.load();
    expect(provider.executions.any((AgentActionExecution e) => e.id == 'old-exec'), isFalse);

    final record = AgentActionRemoteAuditRecord(
      id: 'audit-old',
      occurredAtUtc: DateTime.utc(2026, 5, 15, 11),
      rpcMethod: 'agent.action.run',
      outcome: 'success',
      credentialPresent: false,
      actionId: 'action-1',
      executionId: 'old-exec',
    );
    final result = await provider.focusExecutionFromRemoteAudit(record);

    expect(result, AgentActionRemoteAuditFocusResult.succeeded);
    expect(provider.auditCorrelationExecutionId, 'old-exec');
    expect(provider.executions.any((AgentActionExecution e) => e.id == 'old-exec'), isTrue);
  });

  test('focusExecutionFromRemoteAudit should fail when runtime instance mismatches execution', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.executions['execution-1'] = AgentActionExecution(
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

    await provider.load();

    final record = AgentActionRemoteAuditRecord(
      id: 'audit-mismatch',
      occurredAtUtc: DateTime.utc(2026, 5, 15, 11),
      rpcMethod: 'agent.action.run',
      outcome: 'success',
      credentialPresent: false,
      actionId: 'action-1',
      executionId: 'execution-1',
      runtimeInstanceId: 'inst-on-audit',
    );
    final result = await provider.focusExecutionFromRemoteAudit(record);

    expect(result, AgentActionRemoteAuditFocusResult.runtimeInstanceMismatch);
    expect(provider.auditCorrelationExecutionId, isNull);
    expect(provider.selectedActionId, 'action-1');
  });

  test('focusExecutionFromRemoteAudit should fail runtime mismatch after fetch', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.executions['execution-remote'] = AgentActionExecution(
      id: 'execution-remote',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime(2020),
      source: AgentActionRequestSource.remoteHub,
      finishedAt: DateTime(2020, 1, 1, 1),
      redactionApplied: true,
      runtimeInstanceId: 'inst-on-execution',
    );

    await provider.load();
    expect(provider.executions.any((AgentActionExecution e) => e.id == 'execution-remote'), isFalse);

    final record = AgentActionRemoteAuditRecord(
      id: 'audit-fetch-mismatch',
      occurredAtUtc: DateTime.utc(2026, 5, 15, 11),
      rpcMethod: 'agent.action.run',
      outcome: 'success',
      credentialPresent: false,
      actionId: 'action-1',
      executionId: 'execution-remote',
      runtimeInstanceId: 'inst-on-audit',
    );

    final result = await provider.focusExecutionFromRemoteAudit(record);

    expect(result, AgentActionRemoteAuditFocusResult.runtimeInstanceMismatch);
    expect(provider.auditCorrelationExecutionId, isNull);
    expect(provider.executions.any((AgentActionExecution e) => e.id == 'execution-remote'), isFalse);
  });

  test('sliceCapturedOutput should return utf8 window from chunked store', () async {
    const payload = 'segment-payload-xyz';
    repository.setChunkedCapturedOutput(
      executionId: 'exec-chunk',
      stream: AgentActionCapturedOutputConstants.stdoutStream,
      text: payload,
    );

    final result = await provider.sliceCapturedOutput(
      executionId: 'exec-chunk',
      stream: AgentActionCapturedOutputConstants.stdoutStream,
      offsetUtf8: 0,
      maxBytes: 8,
    );

    expect(result.isSuccess(), isTrue);
    final window = result.getOrThrow();
    expect(window.text, 'segment-');
    expect(window.totalBytes, payload.length);
    expect(window.responseTruncated, isTrue);
  });

  test('focusExecutionFromRemoteAudit should fetch chunked execution without hydrating stdout', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.setChunkedCapturedOutput(
      executionId: 'old-chunk-exec',
      stream: AgentActionCapturedOutputConstants.stdoutStream,
      text: 'stored-only-in-chunks',
    );
    repository.executions['old-chunk-exec'] = AgentActionExecution(
      id: 'old-chunk-exec',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime(2020),
      source: AgentActionRequestSource.remoteHub,
      finishedAt: DateTime(2020, 1, 1, 1),
      stdoutStoredInChunks: true,
      redactionApplied: true,
    );

    await provider.load();
    expect(provider.executions.any((AgentActionExecution e) => e.id == 'old-chunk-exec'), isFalse);

    final record = AgentActionRemoteAuditRecord(
      id: 'audit-chunk',
      occurredAtUtc: DateTime.utc(2026, 5, 15, 11),
      rpcMethod: 'agent.action.run',
      outcome: 'success',
      credentialPresent: false,
      actionId: 'action-1',
      executionId: 'old-chunk-exec',
    );
    final result = await provider.focusExecutionFromRemoteAudit(record);

    expect(result, AgentActionRemoteAuditFocusResult.succeeded);
    expect(repository.lastGetExecutionHydrateCapturedOutput, isFalse);
    final merged = provider.executions.singleWhere((AgentActionExecution e) => e.id == 'old-chunk-exec');
    expect(merged.stdoutStoredInChunks, isTrue);
    expect(merged.stdoutText, isNull);
  });

  test('cancels running execution and reloads history', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.executions['execution-1'] = AgentActionExecution(
      id: 'execution-1',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.running,
      requestedAt: DateTime(2026, 5, 15, 9),
      source: AgentActionRequestSource.localUi,
      pid: 1234,
    );

    await provider.load();
    final execution = provider.executions.single;

    expect(provider.canCancelExecution(execution), isTrue);

    await provider.cancelExecution(execution);

    expect(provider.errorMessage, isNull);
    expect(provider.hasCancellationInProgress(execution.id), isFalse);
    expect(provider.executions.single.status, AgentActionExecutionStatus.killed);
    expect(repository.savedExecutions.single.status, AgentActionExecutionStatus.killed);
  });

  test('filters selected action history by status, source and period', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.executions['old-failed'] = AgentActionExecution(
      id: 'old-failed',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.failed,
      requestedAt: DateTime(2026, 5, 11, 12),
      source: AgentActionRequestSource.scheduler,
    );
    repository.executions['recent-failed'] = AgentActionExecution(
      id: 'recent-failed',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.failed,
      requestedAt: DateTime(2026, 5, 15, 11),
      source: AgentActionRequestSource.scheduler,
    );
    repository.executions['recent-success'] = AgentActionExecution(
      id: 'recent-success',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime(2026, 5, 15, 10),
      source: AgentActionRequestSource.localUi,
    );

    await provider.load();
    provider.setHistoryStatusFilter(AgentActionExecutionStatus.failed);
    provider.setHistorySourceFilter(AgentActionRequestSource.scheduler);
    provider.setHistoryPeriodFilter(AgentActionHistoryPeriod.last24Hours);

    expect(
      provider.filteredSelectedExecutions.map((execution) => execution.id),
      ['recent-failed'],
    );
  });

  test('should filter saved actions by type and search query', () async {
    repository.definitions['cmd'] = const AgentActionDefinition(
      id: 'cmd',
      name: 'Backup command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.definitions['email'] = const AgentActionDefinition(
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

    await provider.load();
    provider.selectAction('email');
    provider.setDefinitionTypeFilter(AgentActionType.email);

    expect(provider.filteredDefinitions.map((definition) => definition.id), ['email']);

    provider.setDefinitionTypeFilter(null);
    provider.selectAction('cmd');
    provider.setDefinitionSearchQuery('backup');

    expect(provider.filteredDefinitions.map((definition) => definition.id), ['cmd']);
  });

  test('should filter execution history by failure phase', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.executions['preflight-fail'] = AgentActionExecution(
      id: 'preflight-fail',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.failed,
      requestedAt: DateTime(2026, 5, 15, 11),
      source: AgentActionRequestSource.localUi,
      failurePhase: 'execution_preflight',
    );
    repository.executions['exit-fail'] = AgentActionExecution(
      id: 'exit-fail',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.failed,
      requestedAt: DateTime(2026, 5, 15, 10),
      source: AgentActionRequestSource.localUi,
      failurePhase: 'process_exit',
    );

    await provider.load();
    provider.setHistoryFailurePhaseFilter('process_exit');

    expect(
      provider.filteredSelectedExecutions.map((execution) => execution.id),
      ['exit-fail'],
    );
  });

  test('should keep selected action visible when list filters hide it', () async {
    repository.definitions['cmd'] = const AgentActionDefinition(
      id: 'cmd',
      name: 'Command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.definitions['email'] = const AgentActionDefinition(
      id: 'email',
      name: 'Email',
      state: AgentActionState.active,
      config: EmailActionConfig(
        smtpProfileId: 'smtp-local',
        from: 'agent@example.com',
        to: <String>['ops@example.com'],
        subjectTemplate: 'Done',
        bodyTemplate: 'Finished',
      ),
    );

    await provider.load();
    provider.selectAction('cmd');
    provider.setDefinitionTypeFilter(AgentActionType.email);

    expect(provider.filteredDefinitions.map((definition) => definition.id), ['cmd', 'email']);
  });

  test('loads only executions within the visible retention window', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    repository.executions['outside-window'] = AgentActionExecution(
      id: 'outside-window',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime(2026, 5, 11, 11, 59),
      source: AgentActionRequestSource.localUi,
    );
    repository.executions['inside-window'] = AgentActionExecution(
      id: 'inside-window',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime(2026, 5, 12, 12),
      source: AgentActionRequestSource.localUi,
    );

    await provider.load();

    expect(provider.executions.map((execution) => execution.id), [
      'inside-window',
    ]);
  });

  test('should export and import action bundle through provider file helpers', () async {
    repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Export me',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: r'echo ${secret:api_key}'),
    );
    repository.triggers['trigger-1'] = const AgentActionTrigger(
      id: 'trigger-1',
      actionId: 'action-1',
      type: AgentActionTriggerType.daily,
      schedule: AgentActionTriggerSchedule(
        timeOfDayMinutes: 480,
        timezoneId: 'America/Sao_Paulo',
      ),
    );

    await provider.load();

    final exportFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}agent_actions_bundle_export_test.json',
    );
    if (exportFile.existsSync()) {
      exportFile.deleteSync();
    }

    final exported = await provider.exportBundleToFile(exportFile.path);
    expect(exported, isTrue);
    expect(exportFile.existsSync(), isTrue);

    repository.definitions.clear();
    repository.triggers.clear();

    final imported = await provider.importBundleFromFile(exportFile.path);
    expect(imported, isNotNull);
    expect(imported!.importedDefinitionIds, ['action-1']);
    expect(imported.importedTriggerIds, ['trigger-1']);
    expect(imported.secretPlaceholderNames, contains('api_key'));
    expect(repository.definitions['action-1']?.state, AgentActionState.needsValidation);
    expect(repository.triggers['trigger-1']?.isEnabled, isFalse);

    exportFile.deleteSync();
  });
}

AgentActionsProvider _buildProvider({
  required _FakeAgentActionRepository repository,
  required FeatureFlags featureFlags,
  required ActionExecutionQueue executionQueue,
  required _FakeDeveloperData7ConnectionGateway developerData7ConnectionGateway,
  AgentActionLocalRunnerRegistry? runnerRegistry,
  IComObjectInvocationDiagnostics? comObjectInvocationDiagnostics,
  AgentActionTriggerScheduler? triggerScheduler,
}) {
  final runners = runnerRegistry ??
      AgentActionLocalRunnerRegistry([
        const _FakeAgentActionLocalRunner(),
        const _FakeDeveloperActionLocalRunner(),
      ]);
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
  final saveDefinition = SaveAgentActionDefinition(
    repository,
    validateDefinition,
    const AgentActionDefinitionSnapshotter(),
    featureFlags,
  );
  const portableCodec = AgentActionPortableCodec();
  final backupSanitizer = AgentActionBackupSanitizer(codec: portableCodec);

  return AgentActionsProvider(
    ListAgentActionDefinitions(repository),
    ListAgentActionExecutions(repository),
    saveDefinition,
    DeleteAgentActionDefinition(repository),
    ListAgentActionTriggers(repository),
    DeleteAgentActionTrigger(repository),
    SaveAgentActionTrigger(
      repository,
      const ValidateAgentActionTrigger(),
      featureFlags,
    ),
    ListDeveloperData7Connections(developerData7ConnectionGateway),
    RunAgentActionLocally(
      repository,
      runners,
      const Uuid(),
      executionQueue: executionQueue,
      featureFlags: featureFlags,
    ),
    TestAgentActionDefinition(repository, validateDefinition),
    previewDefinition,
    CancelAgentActionExecution(
      repository,
      runners,
      executionQueue: executionQueue,
    ),
    GetAgentActionExecution(repository),
    SliceAgentActionCapturedOutput(repository),
    ListRecentAgentActionRemoteAudit(_StubRemoteAuditStore()),
    ExportAgentActionsBundle(
      ListAgentActionDefinitions(repository),
      ListAgentActionTriggers(repository),
      backupSanitizer,
    ),
    ImportAgentActionsBundle(
      saveDefinition,
      SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      ),
      backupSanitizer,
    ),
    featureFlags,
    const Uuid(),
    triggerScheduler: triggerScheduler,
    comObjectInvocationDiagnostics: comObjectInvocationDiagnostics,
    now: () => DateTime(2026, 5, 15, 12),
  );
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
          'catalog_connection_count': 2,
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
        stdout: AgentActionCapturedOutput.disabled,
        stderr: AgentActionCapturedOutput.disabled,
        redactionApplied: true,
      ),
    );
  }

  @override
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
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

class _FakeComObjectInvocationDiagnostics implements IComObjectInvocationDiagnostics {
  const _FakeComObjectInvocationDiagnostics({this.registeredHandlerCount = 0});

  @override
  final int registeredHandlerCount;
}

class _FakeComObjectLocalRunner implements AgentActionLocalRunner {
  const _FakeComObjectLocalRunner();

  @override
  AgentActionType get type => AgentActionType.comObject;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    return Success(
      AgentActionProcessResult(
        status: AgentActionExecutionStatus.succeeded,
        pid: 1,
        exitCode: 0,
        processStartedAt: DateTime(2026, 5, 15, 9),
        finishedAt: DateTime(2026, 5, 15, 9, 1),
        stdout: AgentActionCapturedOutput.disabled,
        stderr: AgentActionCapturedOutput.disabled,
        redactionApplied: true,
      ),
    );
  }

  @override
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
  }) async {
    return Success(
      AgentActionCancellationResult(
        executionId: executionId,
        status: AgentActionExecutionStatus.cancelled,
        killed: false,
        pid: 1,
        message: 'Cancelled.',
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
        stdout: AgentActionCapturedOutput.disabled,
        stderr: AgentActionCapturedOutput.disabled,
        redactionApplied: true,
      ),
    );
  }

  @override
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
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
  final List<AgentActionExecution> savedExecutions = [];
  final Map<String, Map<String, String>> _chunkedCapturedOutputByExecution = {};

  bool? lastGetExecutionHydrateCapturedOutput;

  void setChunkedCapturedOutput({
    required String executionId,
    required String stream,
    required String text,
  }) {
    _chunkedCapturedOutputByExecution.putIfAbsent(executionId, () => <String, String>{})[stream] = text;
  }

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
    savedExecutions.add(execution);
    executions[execution.id] = execution;
    return Success(execution);
  }

  @override
  Future<Result<AgentActionExecution>> getExecution(
    String id, {
    bool hydrateCapturedOutput = true,
  }) async {
    lastGetExecutionHydrateCapturedOutput = hydrateCapturedOutput;
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
  Future<Result<CapturedOutputUtf8Window>> sliceCapturedOutput({
    required String executionId,
    required String stream,
    required int offsetUtf8,
    required int maxBytes,
  }) async {
    final text = _chunkedCapturedOutputByExecution[executionId]?[stream];
    if (text == null || text.isEmpty) {
      return Success(
        (
          text: '',
          nextOffset: offsetUtf8,
          totalBytes: 0,
          responseTruncated: false,
          effectiveStart: offsetUtf8,
        ),
      );
    }

    return Success(sliceUtf8TextWindow(text, offsetUtf8, maxBytes));
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

  @override
  Future<Result<int>> clearCapturedOutputOlderThan({
    required DateTime olderThan,
  }) async {
    return const Success(0);
  }
}

class _ProviderTestHeldSchedulerLock implements IAgentActionSchedulerInstanceLock {
  @override
  bool get isHeld => true;

  @override
  Future<Result<Unit>> tryAcquire() async {
    return Failure(
      ActionAuthorizationFailure.withContext(
        message: 'Scheduler lock is held.',
        code: AgentActionFailureCode.schedulerBootstrapFailed,
        context: const {
          'reason': AgentActionTriggerConstants.schedulerInstanceLockedReason,
        },
      ),
    );
  }

  @override
  Future<void> release() async {}
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
