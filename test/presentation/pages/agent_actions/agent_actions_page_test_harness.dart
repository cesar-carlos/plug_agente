import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_backup_sanitizer.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_secret_availability_checker.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/rpc/agent_action_execution_output_pager.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_trigger.dart';
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
import 'package:plug_agente/application/use_cases/save_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/slice_agent_action_captured_output.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_trigger.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/settings/agent_action_preflight_settings.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_scheduler_instance_lock.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_com_object_invocation_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_developer_data7_connection_gateway.dart';
import 'package:plug_agente/infrastructure/actions/action_command_safety_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_actions_bundle_file_gateway.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_portable_codec.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_actions_page.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_provider_dependencies.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_help_button.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

Finder agentActionFormTextBox(String label) {
  return find.descendant(
    of: find.byWidgetPredicate(
      (widget) => widget is AppTextField && widget.label == label,
    ),
    matching: find.byType(TextBox),
  );
}

Finder formComboBox(String label) {
  return find.descendant(
    of: find.byWidgetPredicate(
      (widget) => widget is AppDropdown<dynamic> && widget.label == label,
    ),
    matching: find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString().startsWith('ComboBox<'),
    ),
  );
}

Finder agentActionFormHelpButton(String label) {
  final field = find.byWidgetPredicate(
    (widget) {
      return (widget is AppTextField && widget.label == label) ||
          (widget is AppDropdown<dynamic> && widget.label == label);
    },
  );
  return find.descendant(
    of: field,
    matching: find.byType(AppHelpButton),
  );
}

Finder agentActionFormHelpButtonByKey(String label) {
  return find.byKey(ValueKey<String>('app_help_button_${helpButtonKeyToken(label)}'));
}

String helpButtonKeyToken(String label) {
  var token = label.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
  while (token.startsWith('_')) {
    token = token.substring(1);
  }
  while (token.endsWith('_')) {
    token = token.substring(0, token.length - 1);
  }
  return token;
}

Finder agentActionFormComboBox(String label) {
  final key = switch (label) {
    'Tipo' || 'Type' => 'agent_action_editor_type_dropdown',
    'Modo PowerShell' || 'PowerShell mode' => 'agent_action_editor_powershell_mode_dropdown',
    'Executavel PowerShell' || 'PowerShell executable' => 'agent_action_editor_powershell_executable_dropdown',
    _ => throw StateError('Unknown action form combo box label: $label'),
  };

  return agentActionFormComboBoxByKey(key);
}

Finder agentActionFormComboBoxByKey(String key) {
  return find.descendant(
    of: find.byKey(ValueKey<String>(key)),
    matching: find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString().startsWith('ComboBox<'),
    ),
  );
}

Finder agentActionFormTextBoxByKey(String key) {
  return find.descendant(
    of: find.byKey(ValueKey<String>(key)),
    matching: find.byType(TextBox),
  );
}

Finder filledButtonWithText(String text) {
  return find.ancestor(
    of: find.text(text),
    matching: find.byType(FilledButton),
  );
}

void drainPendingFlutterErrors(WidgetTester tester) {
  while (tester.takeException() != null) {}
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

Future<void> openCreateActionDialog(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await tester.tap(find.widgetWithText(FilledButton, l10n.agentActionsFormNew).first);
  await tester.pumpAndSettle();
  expect(find.byType(ContentDialog), findsOneWidget);
}

Future<void> selectActionFormType(WidgetTester tester, AppLocalizations l10n, String typeLabel) async {
  await tester.tap(agentActionFormComboBox(l10n.agentActionsFormType));
  await tester.pumpAndSettle();
  await tester.tap(find.text(typeLabel).last);
  await tester.pumpAndSettle();
}

Future<void> selectPowerShellMode(WidgetTester tester, AppLocalizations l10n, String modeLabel) async {
  await tester.tap(agentActionFormComboBox(l10n.agentActionsFormPowerShellMode));
  await tester.pumpAndSettle();
  await tester.tap(find.text(modeLabel).last);
  await tester.pumpAndSettle();
}

Future<void> selectPowerShellExecutable(WidgetTester tester, AppLocalizations l10n, String executableLabel) async {
  await tester.tap(agentActionFormComboBox(l10n.agentActionsFormPowerShellExecutable));
  await tester.pumpAndSettle();
  await tester.tap(find.text(executableLabel).last);
  await tester.pumpAndSettle();
}

Future<void> openSelectedActionDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('agent_action_definition_more_action-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey<String>('agent_action_definition_edit_action-1')));
  await tester.pumpAndSettle();
  expect(find.byType(ContentDialog), findsAtLeastNWidgets(1));
}

Future<void> openActionDetailsDialog(WidgetTester tester, String actionId) async {
  await tester.tap(find.byKey(ValueKey<String>('agent_action_definition_more_$actionId')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey<String>('agent_action_definition_details_$actionId')));
  await tester.pumpAndSettle();
  expect(find.byType(ContentDialog), findsOneWidget);
}

Future<void> setResponsiveTestWindow(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
}

Future<void> openCreateTriggerDialog(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.widgetWithText(Button, l10n.agentActionsTriggerAdd).last);
  await tester.pumpAndSettle();
  expect(find.text(l10n.agentActionsTriggerEditorTitleNew), findsOneWidget);
}

Future<void> selectTriggerType(WidgetTester tester, AppLocalizations l10n, String typeLabel) async {
  await tester.tap(formComboBox(l10n.agentActionsTriggerFieldType));
  await tester.pumpAndSettle();
  await tester.tap(find.text(typeLabel).last);
  await tester.pumpAndSettle();
}

String triggerTypeTestLabel(AgentActionTriggerType type, AppLocalizations l10n) {
  return switch (type) {
    AgentActionTriggerType.manual => l10n.agentActionsTriggerTypeManual,
    AgentActionTriggerType.remote => l10n.agentActionsTriggerTypeRemote,
    AgentActionTriggerType.once => l10n.agentActionsTriggerTypeOnce,
    AgentActionTriggerType.interval => l10n.agentActionsTriggerTypeInterval,
    AgentActionTriggerType.daily => l10n.agentActionsTriggerTypeDaily,
    AgentActionTriggerType.weekly => l10n.agentActionsTriggerTypeWeekly,
    AgentActionTriggerType.monthly => l10n.agentActionsTriggerTypeMonthly,
    AgentActionTriggerType.appStart => l10n.agentActionsTriggerTypeAppStart,
    AgentActionTriggerType.appClose => l10n.agentActionsTriggerTypeAppClose,
  };
}

class HeldSchedulerInstanceLockForPageTest implements IAgentActionSchedulerInstanceLock {
  const HeldSchedulerInstanceLockForPageTest({
    this.reason = AgentActionTriggerConstants.schedulerInstanceLockedReason,
  });

  final String reason;

  @override
  bool get isHeld => true;

  @override
  Future<Result<Unit>> tryAcquire() async {
    return Failure(
      ActionAuthorizationFailure.withContext(
        message: 'Scheduler lock is held.',
        code: AgentActionFailureCode.schedulerBootstrapFailed,
        context: {
          'reason': reason,
        },
      ),
    );
  }

  @override
  Future<void> release() async {}
}

class AgentActionsPageHarness {
  AgentActionsPageHarness({
    IDeveloperData7ConnectionGateway? developerConnectionGateway,
    IAgentActionRemoteAuditStore? remoteAuditStore,
    AgentActionTriggerScheduler? triggerScheduler,
    AgentActionRuntimeStateGuard? runtimeStateGuard,
    RuntimeCapabilities? runtimeCapabilities,
    RuntimeDetectionDiagnostics? runtimeDiagnostics,
    IComObjectInvocationDiagnostics? comObjectInvocationDiagnostics,
    bool withActionSecretStore = false,
    bool includeComObjectRunner = false,
    bool useExecutionQueue = true,
  }) : _developerConnectionGateway = developerConnectionGateway ?? FakeDeveloperData7ConnectionGateway(),
       _remoteAuditStore = remoteAuditStore ?? StubRemoteAuditStore(),
       _runtimeStateGuard = runtimeStateGuard,
       _runtimeCapabilities = runtimeCapabilities ?? RuntimeCapabilities.full(),
       _runtimeDiagnostics = runtimeDiagnostics,
       _actionSecretStore = withActionSecretStore ? HarnessAgentActionSecretStore() : null {
    final validateDefinition = ValidateAgentActionDefinition(
      AgentActionAdapterRegistry([
        const FakeCommandLineActionAdapter(),
        const FakeScriptActionAdapter(),
        const FakeDeveloperActionAdapter(),
      ]),
    );
    final previewDefinition = PreviewAgentActionDefinition(
      repository,
      AgentActionAdapterRegistry([
        const FakeCommandLineActionAdapter(),
        const FakeScriptActionAdapter(),
        const FakeDeveloperActionAdapter(),
      ]),
    );
    final runnerRegistry = AgentActionLocalRunnerRegistry([
      const FakeAgentActionLocalRunner(),
      const FakeDeveloperActionLocalRunner(),
      if (includeComObjectRunner) const FakeComObjectLocalRunner(),
    ]);
    final saveDefinition = SaveAgentActionDefinition(
      repository,
      validateDefinition,
      const AgentActionDefinitionSnapshotter(),
      featureFlags,
      preflightSettings: preflightSettings,
    );
    const portableCodec = AgentActionPortableCodec();
    final backupSanitizer = AgentActionBackupSanitizer(codec: portableCodec);

    provider = AgentActionsProvider(
      AgentActionsProviderDependencies(
        listDefinitions: ListAgentActionDefinitions(repository),
        listExecutions: ListAgentActionExecutions(repository),
        saveDefinition: saveDefinition,
        deleteDefinition: DeleteAgentActionDefinition(repository),
        listTriggers: ListAgentActionTriggers(repository),
        deleteTrigger: DeleteAgentActionTrigger(repository),
        saveTrigger: SaveAgentActionTrigger(
          repository,
          const ValidateAgentActionTrigger(),
          featureFlags,
        ),
        listDeveloperData7Connections: ListDeveloperData7Connections(_developerConnectionGateway),
        runAction: RunAgentActionLocally(
          repository,
          runnerRegistry,
          const Uuid(),
          executionQueue: executionQueue,
          featureFlags: featureFlags,
        ),
        testDefinition: TestAgentActionDefinition(repository, validateDefinition),
        previewDefinition: previewDefinition,
        cancelExecution: CancelAgentActionExecution(
          repository,
          runnerRegistry,
          executionQueue: executionQueue,
        ),
        getExecution: GetAgentActionExecution(repository),
        sliceCapturedOutput: SliceAgentActionCapturedOutput(repository),
        listRecentRemoteAudit: ListRecentAgentActionRemoteAudit(_remoteAuditStore),
        exportBundle: ExportAgentActionsBundle(
          ListAgentActionDefinitions(repository),
          ListAgentActionTriggers(repository),
          backupSanitizer,
        ),
        importBundle: ImportAgentActionsBundle(
          saveDefinition,
          SaveAgentActionTrigger(
            repository,
            const ValidateAgentActionTrigger(),
            featureFlags,
          ),
          backupSanitizer,
        ),
        featureFlags: featureFlags,
        uuid: const Uuid(),
        commandSafetyAssessor: const ActionCommandSafetyValidator(),
        retentionSettings: retentionSettings,
        bundleFileGateway: const AgentActionsBundleFileGateway(),
      ),
      triggerScheduler: triggerScheduler,
      comObjectInvocationDiagnostics: comObjectInvocationDiagnostics,
      runtimeStateGuard: _runtimeStateGuard,
      executionQueue: useExecutionQueue ? executionQueue : null,
      secretAvailabilityChecker: _actionSecretStore == null
          ? null
          : AgentActionSecretAvailabilityChecker(secretStore: _actionSecretStore),
      saveAgentActionSecret: _actionSecretStore == null ? null : SaveAgentActionSecret(_actionSecretStore),
      deleteAgentActionSecret: _actionSecretStore == null ? null : DeleteAgentActionSecret(_actionSecretStore),
      now: () => DateTime(2026, 5, 15, 12),
      preflightSettings: preflightSettings,
    );
  }

  final HarnessAgentActionSecretStore? _actionSecretStore;
  final FakeAgentActionRepository repository = FakeAgentActionRepository();
  final InMemoryAppSettingsStore appSettingsStore = InMemoryAppSettingsStore();
  late final AgentActionRetentionSettings retentionSettings = AgentActionRetentionSettings(appSettingsStore);
  late final AgentActionPreflightSettings preflightSettings = AgentActionPreflightSettings(appSettingsStore);
  late final FeatureFlags featureFlags = FeatureFlags(appSettingsStore);
  final ActionExecutionQueue executionQueue = ActionExecutionQueue();
  final IDeveloperData7ConnectionGateway _developerConnectionGateway;
  final IAgentActionRemoteAuditStore _remoteAuditStore;
  final AgentActionRuntimeStateGuard? _runtimeStateGuard;
  final RuntimeCapabilities _runtimeCapabilities;
  final RuntimeDetectionDiagnostics? _runtimeDiagnostics;
  late final AgentActionsProvider provider;

  Future<void> pumpPage(
    WidgetTester tester, {
    Size? size,
  }) async {
    if (size != null) {
      await tester.binding.setSurfaceSize(size);
    }
    await tester.pumpWidget(buildWidget());
    await tester.pump();
    while (provider.isLoading) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

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
    if (getIt.isRegistered<AgentActionRetentionSettings>()) {
      getIt.unregister<AgentActionRetentionSettings>();
    }
    getIt.registerSingleton<AgentActionRetentionSettings>(retentionSettings);
    if (getIt.isRegistered<AgentActionPreflightSettings>()) {
      getIt.unregister<AgentActionPreflightSettings>();
    }
    getIt.registerSingleton<AgentActionPreflightSettings>(preflightSettings);
    if (getIt.isRegistered<IAppSettingsStore>()) {
      getIt.unregister<IAppSettingsStore>();
    }
    getIt.registerSingleton<IAppSettingsStore>(appSettingsStore);

    return FluentApp(
      locale: const Locale('pt'),
      theme: FluentThemeData(visualDensity: VisualDensity.standard),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<AgentActionsProvider>.value(
        value: provider,
        child: AgentActionsPage(
          runtimeCapabilities: _runtimeCapabilities,
          runtimeDiagnostics: _runtimeDiagnostics,
          appSettingsStore: appSettingsStore,
        ),
      ),
    );
  }
}

class FakeCommandLineActionAdapter implements AgentActionAdapter {
  const FakeCommandLineActionAdapter();

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

class FakeScriptActionAdapter implements AgentActionAdapter {
  const FakeScriptActionAdapter();

  @override
  AgentActionType get type => AgentActionType.script;

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
        redactedCommandPreview: 'powershell.exe -File ***',
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

class FakeDeveloperActionAdapter implements AgentActionAdapter {
  const FakeDeveloperActionAdapter();

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

class FakeAgentActionLocalRunner implements AgentActionLocalRunner {
  const FakeAgentActionLocalRunner();

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

class FakeComObjectInvocationDiagnostics implements IComObjectInvocationDiagnostics {
  const FakeComObjectInvocationDiagnostics({this.registeredHandlerCount = 0});

  @override
  final int registeredHandlerCount;
}

class FakeComObjectLocalRunner implements AgentActionLocalRunner {
  const FakeComObjectLocalRunner();

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
        stdout: const AgentActionCapturedOutput(
          text: '',
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

class FakeDeveloperActionLocalRunner implements AgentActionLocalRunner {
  const FakeDeveloperActionLocalRunner();

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

class MultiDeveloperData7ConnectionGateway implements IDeveloperData7ConnectionGateway {
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

class FakeDeveloperData7ConnectionGateway implements IDeveloperData7ConnectionGateway {
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

class MissingDeveloperData7ConnectionGateway implements IDeveloperData7ConnectionGateway {
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

class FakeAgentActionRepository implements IAgentActionRepository {
  final Map<String, AgentActionDefinition> definitions = {};
  final Map<String, AgentActionTrigger> triggers = {};
  final Map<String, AgentActionExecution> executions = {};
  final Map<String, Map<String, String>> _chunkedCapturedOutputByExecution = {};

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
    executions[execution.id] = execution;
    return Success(execution);
  }

  @override
  Future<Result<AgentActionExecution>> getExecution(
    String id, {
    bool hydrateCapturedOutput = true,
  }) async {
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

class StubRemoteAuditStore implements IAgentActionRemoteAuditStore {
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

class FakeRemoteAuditStore implements IAgentActionRemoteAuditStore {
  FakeRemoteAuditStore({required this.records});

  final List<AgentActionRemoteAuditRecord> records;

  @override
  Future<void> append(AgentActionRemoteAuditRecord record) async {}

  @override
  Future<List<AgentActionRemoteAuditRecord>> listRecent({int limit = 200}) async {
    if (limit <= 0) {
      return <AgentActionRemoteAuditRecord>[];
    }
    return records.take(limit).toList(growable: false);
  }

  @override
  Future<int> deleteWhereOccurredBefore({
    required DateTime cutoffUtc,
    required int limit,
  }) async => 0;
}

class HarnessAgentActionSecretStore implements IAgentActionSecretStore {
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
