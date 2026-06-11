import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_subsystem_coordinator.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/actions/i_action_command_safety_assessor.dart';
import 'package:plug_agente/application/bootstrap/deferred_boot_phase_outcome.dart';
import 'package:plug_agente/application/bootstrap/hub_connection_shutdown_registry.dart';
import 'package:plug_agente/application/ports/i_agent_actions_bundle_file_gateway.dart';
import 'package:plug_agente/application/repositories/i_app_preferences_repository.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/services/hub_access_token_refresh_gate.dart';
import 'package:plug_agente/application/services/hub_access_token_renewer.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/cancel_all_notifications.dart';
import 'package:plug_agente/application/use_cases/cancel_notification.dart';
import 'package:plug_agente/application/use_cases/check_hub_availability.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/application/use_cases/export_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/get_client_token_secret.dart';
import 'package:plug_agente/application/use_cases/import_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_definitions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_triggers.dart';
import 'package:plug_agente/application/use_cases/list_client_tokens.dart';
import 'package:plug_agente/application/use_cases/list_developer_data7_connections.dart';
import 'package:plug_agente/application/use_cases/list_recent_agent_action_remote_audit.dart';
import 'package:plug_agente/application/use_cases/load_agent_config.dart';
import 'package:plug_agente/application/use_cases/prepare_elevated_action_runner.dart';
import 'package:plug_agente/application/use_cases/preview_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/save_agent_config.dart';
import 'package:plug_agente/application/use_cases/schedule_notification.dart';
import 'package:plug_agente/application/use_cases/send_notification.dart';
import 'package:plug_agente/application/use_cases/set_start_with_windows.dart';
import 'package:plug_agente/application/use_cases/set_tray_behavior_preference.dart';
import 'package:plug_agente/application/use_cases/slice_agent_action_captured_output.dart';
import 'package:plug_agente/application/use_cases/sync_startup_status.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/hub_resilience_config.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/settings/agent_action_preflight_settings.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_com_object_invocation_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_protocol_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/presentation/adapters/connection_provider_playground_db_gateway.dart';
import 'package:plug_agente/presentation/adapters/hub_recovery_auth_bridge.dart';
import 'package:plug_agente/presentation/app/app.dart';
import 'package:plug_agente/presentation/boot/startup_auto_session_initializer.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_provider_dependencies.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_provider_factory.dart';
import 'package:plug_agente/presentation/providers/agent_operational_readiness_provider.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/presentation/providers/notification_provider.dart';
import 'package:plug_agente/presentation/providers/playground_provider.dart';
import 'package:plug_agente/presentation/providers/presentation_infrastructure_providers.dart';
import 'package:plug_agente/presentation/providers/runtime_mode_provider.dart';
import 'package:plug_agente/presentation/providers/sql_investigation_provider.dart';
import 'package:plug_agente/presentation/providers/system_settings_provider.dart';
import 'package:plug_agente/presentation/providers/theme_provider.dart';
import 'package:plug_agente/presentation/providers/updates_settings_provider.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({
    required this.capabilities,
    this.initialRoute,
    this.runDeferredBootstrap,
    super.key,
  });

  final RuntimeCapabilities capabilities;
  final String? initialRoute;
  final Future<DeferredBootPhaseOutcome> Function()? runDeferredBootstrap;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ...buildPresentationInfrastructureProviders(capabilities: capabilities),
        ChangeNotifierProvider(
          create: (context) => RuntimeModeProvider(getIt<RuntimeCapabilities>()),
        ),
        ChangeNotifierProvider(
          create: (context) => ThemeProvider(getIt<IAppPreferencesRepository>()),
        ),
        ChangeNotifierProvider(
          create: (context) => SystemSettingsProvider(
            getIt<IStartupPreferencesRepository>(),
            syncStartupStatus: getIt<SyncStartupStatus>(),
            setStartWithWindows: getIt<SetStartWithWindows>(),
            setTrayBehaviorPreference: getIt<SetTrayBehaviorPreference>(),
          ),
        ),
        if (getIt.isRegistered<IAutoUpdateOrchestrator>())
          ChangeNotifierProvider(
            create: (context) => UpdatesSettingsProvider(
              getIt<IAutoUpdateOrchestrator>(),
              capabilities: getIt<RuntimeCapabilities>(),
              runtimeDiagnostics: getIt.isRegistered<RuntimeDetectionDiagnostics>()
                  ? getIt<RuntimeDetectionDiagnostics>()
                  : null,
            ),
          ),
        ChangeNotifierProvider(
          create: (context) => ConfigProvider(
            getIt<SaveAgentConfig>(),
            getIt<LoadAgentConfig>(),
            getIt<ActiveConfigResolver>(),
            getIt<ConfigService>(),
            getIt<Uuid>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => AuthProvider(
            getIt<HubSessionCoordinator>(),
          ),
        ),
        ChangeNotifierProxyProvider<AuthProvider, ConnectionProvider>(
          create: (context) => ConnectionProvider(
            getIt<ConnectToHub>(),
            getIt<TestDbConnection>(),
            getIt<CheckOdbcDriver>(),
            transportClient: getIt<ITransportClient>(),
            checkHubAvailabilityUseCase: getIt<CheckHubAvailability>(),
            hubResilience: getIt<HubResilienceConfig>(),
            featureFlags: getIt<FeatureFlags>(),
            hubAccessTokenRefreshGate: getIt<HubAccessTokenRefreshGate>(),
            hubAccessTokenRenewer: getIt<HubAccessTokenRenewer>(),
            hubConnectionShutdownRegistry: getIt.isRegistered<HubConnectionShutdownRegistry>()
                ? getIt<HubConnectionShutdownRegistry>()
                : null,
          ),
          update: (context, auth, connection) {
            final bridge = HubRecoveryAuthBridge(
              sessionCoordinator: getIt<HubSessionCoordinator>(),
              authProvider: auth,
            );
            connection!.setHubRecoveryAuthBridge(bridge);
            getIt<HubAccessTokenRenewer>().bindAuthBridge(bridge);
            return connection;
          },
        ),
        ChangeNotifierProvider(
          create: (context) => ClientTokenProvider(
            getIt<CreateClientToken>(),
            getIt<UpdateClientToken>(),
            getIt<ListClientTokens>(),
            getIt<GetClientTokenSecret>(),
            getIt<RevokeClientToken>(),
            getIt<DeleteClientToken>(),
            tokenAuditStore: getIt<ITokenAuditStore>(),
          ),
        ),
        ChangeNotifierProxyProvider2<ConnectionProvider, ClientTokenProvider, AgentOperationalReadinessProvider>(
          create: (context) => AgentOperationalReadinessProvider(
            triggerScheduler: getIt.isRegistered<AgentActionTriggerScheduler>()
                ? getIt<AgentActionTriggerScheduler>()
                : null,
          ),
          update: (context, connection, clientTokens, readiness) {
            readiness!.bind(
              connectionProvider: connection,
              clientTokenProvider: clientTokens,
            );
            return readiness;
          },
        ),
        ChangeNotifierProvider(
          create: (context) => NotificationProvider(
            getIt<SendNotification>(),
            getIt<ScheduleNotification>(),
            getIt<CancelNotification>(),
            getIt<CancelAllNotifications>(),
          ),
        ),
        ChangeNotifierProxyProvider<ConnectionProvider, PlaygroundProvider>(
          create: (context) => PlaygroundProvider(
            getIt<ExecutePlaygroundQuery>(),
            getIt<ExecuteStreamingQuery>(),
          ),
          update: (context, connection, playground) {
            playground!.bindDbConnectionGateway(
              ConnectionProviderPlaygroundDbGateway(connection),
            );
            return playground;
          },
        ),
        ChangeNotifierProvider(
          create: (context) => createAgentActionsProvider(
            AgentActionsProviderWiring(
              dependencies: AgentActionsProviderDependencies(
                listDefinitions: getIt<ListAgentActionDefinitions>(),
                listExecutions: getIt<ListAgentActionExecutions>(),
                saveDefinition: getIt<SaveAgentActionDefinition>(),
                deleteDefinition: getIt<DeleteAgentActionDefinition>(),
                listTriggers: getIt<ListAgentActionTriggers>(),
                deleteTrigger: getIt<DeleteAgentActionTrigger>(),
                saveTrigger: getIt<SaveAgentActionTrigger>(),
                listDeveloperData7Connections: getIt<ListDeveloperData7Connections>(),
                runAction: getIt<RunAgentActionLocally>(),
                testDefinition: getIt<TestAgentActionDefinition>(),
                previewDefinition: getIt<PreviewAgentActionDefinition>(),
                cancelExecution: getIt<CancelAgentActionExecution>(),
                getExecution: getIt<GetAgentActionExecution>(),
                sliceCapturedOutput: getIt<SliceAgentActionCapturedOutput>(),
                listRecentRemoteAudit: getIt<ListRecentAgentActionRemoteAudit>(),
                exportBundle: getIt<ExportAgentActionsBundle>(),
                importBundle: getIt<ImportAgentActionsBundle>(),
                featureFlags: getIt<FeatureFlags>(),
                uuid: getIt<Uuid>(),
                commandSafetyAssessor: getIt<IActionCommandSafetyAssessor>(),
                retentionSettings: getIt<AgentActionRetentionSettings>(),
                bundleFileGateway: getIt<IAgentActionsBundleFileGateway>(),
                saveAgentActionSecret: getIt.isRegistered<SaveAgentActionSecret>() ? getIt<SaveAgentActionSecret>() : null,
                deleteAgentActionSecret: getIt.isRegistered<DeleteAgentActionSecret>() ? getIt<DeleteAgentActionSecret>() : null,
              ),
              preflightSettings: getIt<AgentActionPreflightSettings>(),
              runtimeStateGuard: getIt.isRegistered<AgentActionRuntimeStateGuard>()
                  ? getIt<AgentActionRuntimeStateGuard>()
                  : null,
              subsystemCoordinator: getIt.isRegistered<AgentActionSubsystemCoordinator>()
                  ? getIt<AgentActionSubsystemCoordinator>()
                  : null,
              executionQueue: getIt.isRegistered<ActionExecutionQueue>() ? getIt<ActionExecutionQueue>() : null,
              secretStore: getIt.isRegistered<IAgentActionSecretStore>() ? getIt<IAgentActionSecretStore>() : null,
              elevatedRunnerReadiness: getIt.isRegistered<ElevatedActionRunnerReadinessService>()
                  ? getIt<ElevatedActionRunnerReadinessService>()
                  : null,
              prepareElevatedActionRunner: getIt.isRegistered<PrepareElevatedActionRunner>()
                  ? getIt<PrepareElevatedActionRunner>()
                  : null,
              globalStorageContext: getIt.isRegistered<GlobalStorageContext>() ? getIt<GlobalStorageContext>() : null,
              triggerScheduler: getIt.isRegistered<AgentActionTriggerScheduler>() ? getIt<AgentActionTriggerScheduler>() : null,
              comObjectInvocationDiagnostics: getIt.isRegistered<IComObjectInvocationDiagnostics>()
                  ? getIt<IComObjectInvocationDiagnostics>()
                  : null,
            ),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => WebSocketLogProvider(
            transportClient: getIt<ITransportClient>(),
          ),
        ),
        Provider<IProtocolMetricsCollector>(
          create: (_) => getIt<IProtocolMetricsCollector>(),
        ),
        ChangeNotifierProvider(
          create: (context) => SqlInvestigationProvider(
            getIt<ISqlInvestigationCollector>(),
          ),
        ),
      ],
      child: _ProviderInitializer(
        initialRoute: initialRoute,
        capabilities: capabilities,
        runDeferredBootstrap: runDeferredBootstrap,
      ),
    );
  }
}

class _ProviderInitializer extends StatefulWidget {
  const _ProviderInitializer({
    required this.capabilities,
    this.initialRoute,
    this.runDeferredBootstrap,
  });

  final RuntimeCapabilities capabilities;
  final String? initialRoute;
  final Future<DeferredBootPhaseOutcome> Function()? runDeferredBootstrap;

  @override
  State<_ProviderInitializer> createState() => _ProviderInitializerState();
}

class _ProviderInitializerState extends State<_ProviderInitializer> {
  @override
  void dispose() {
    if (getIt.isRegistered<AgentActionRuntimeStateGuard>()) {
      getIt<AgentActionRuntimeStateGuard>().markDraining(
        reason: AgentActionRuntimeStateConstants.appRootDisposeReason,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StartupAutoSessionInitializer(
      hubSessionCoordinator: getIt<HubSessionCoordinator>(),
      runDeferredBootstrapBeforeConnect: widget.runDeferredBootstrap,
      child: PlugAgentApp(
        initialRoute: widget.initialRoute,
        capabilities: widget.capabilities,
      ),
    );
  }
}
