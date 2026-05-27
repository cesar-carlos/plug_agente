import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:get_it/get_it.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/actions/action_environment_resolver.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_backup_sanitizer.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_remote_lifecycle_audit_recorder.dart';
import 'package:plug_agente/application/actions/agent_action_remote_rate_limiter.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_execution_validator.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_request_validator.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_resolver.dart';
import 'package:plug_agente/application/actions/agent_action_secret_reference_fingerprinter.dart';
import 'package:plug_agente/application/actions/agent_action_subsystem_coordinator.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/agent_actions_remote_capability_provider.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/application/actions/elevated_action_execution_abort_registry.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/actions/elevated_action_status_file_syncer.dart';
import 'package:plug_agente/application/actions/elevated_agent_action_execution_service.dart';
import 'package:plug_agente/application/actions/i_action_command_safety_assessor.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/ports/i_agent_actions_bundle_file_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/services/agent_action_captured_output_periodic_purge.dart';
import 'package:plug_agente/application/services/agent_action_execution_periodic_purge.dart';
import 'package:plug_agente/application/services/agent_action_remote_audit_periodic_purge.dart';
import 'package:plug_agente/application/services/agent_profile_lookup_gateways.dart';
import 'package:plug_agente/application/services/agent_register_profile_provider.dart';
import 'package:plug_agente/application/services/auth_service.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/services/connection_service.dart';
import 'package:plug_agente/application/services/elevated_bridge_artifacts_periodic_purge.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/services/rpc_idempotency_cache_periodic_purge.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/use_cases/apply_agent_action_on_app_exit_policies.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/backfill_agent_action_execution_correlation.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/cancel_all_notifications.dart';
import 'package:plug_agente/application/use_cases/cancel_notification.dart';
import 'package:plug_agente/application/use_cases/check_hub_availability.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/cleanup_agent_action_captured_output.dart';
import 'package:plug_agente/application/use_cases/cleanup_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_agent_action_remote_audit.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_elevated_bridge_artifacts.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_rpc_idempotency_cache.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/dispatch_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/application/use_cases/export_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/application/use_cases/get_client_token_secret.dart';
import 'package:plug_agente/application/use_cases/import_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_definitions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_triggers.dart';
import 'package:plug_agente/application/use_cases/list_client_tokens.dart';
import 'package:plug_agente/application/use_cases/list_developer_data7_connections.dart';
import 'package:plug_agente/application/use_cases/list_recent_agent_action_remote_audit.dart';
import 'package:plug_agente/application/use_cases/load_agent_config.dart';
import 'package:plug_agente/application/use_cases/login_user.dart';
import 'package:plug_agente/application/use_cases/lookup_agent_cep.dart';
import 'package:plug_agente/application/use_cases/lookup_agent_cnpj.dart';
import 'package:plug_agente/application/use_cases/notify_agent_action_execution_if_configured.dart';
import 'package:plug_agente/application/use_cases/prepare_elevated_action_runner.dart';
import 'package:plug_agente/application/use_cases/preview_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/push_agent_profile_to_hub.dart';
import 'package:plug_agente/application/use_cases/reconcile_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/refresh_auth_token.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_via_remote_trigger.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/save_agent_config.dart';
import 'package:plug_agente/application/use_cases/save_auth_token.dart';
import 'package:plug_agente/application/use_cases/schedule_notification.dart';
import 'package:plug_agente/application/use_cases/send_notification.dart';
import 'package:plug_agente/application/use_cases/slice_agent_action_captured_output.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_trigger.dart';
import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/noop_tray_manager_service.dart';
import 'package:plug_agente/core/services/tray_manager_service.dart';
import 'package:plug_agente/core/services/window_manager_service.dart';
import 'package:plug_agente/core/settings/agent_action_preflight_settings.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_orphan_process_terminator.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_portable_codec.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_scheduler_instance_lock.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_agent_actions_remote_capability_provider.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_agent_hub_profile_gateway.dart';
import 'package:plug_agente/domain/repositories/i_auth_client.dart';
import 'package:plug_agente/domain/repositories/i_authorization_cache_metrics.dart';
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_com_object_invocation_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_connected_agents_gateway.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_developer_data7_connection_gateway.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_execution_canceller.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_runner_bridge.dart';
import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_hub_availability_probe.dart';
import 'package:plug_agente/domain/repositories/i_hub_session_store.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_local_app_data_backup_service.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_driver_checker.dart';
import 'package:plug_agente/domain/repositories/i_protocol_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_protocol_negotiator.dart';
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/domain/repositories/i_revoked_token_store.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/actions/action_command_safety_validator.dart';
import 'package:plug_agente/infrastructure/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/agent_actions_bundle_file_gateway.dart';
import 'package:plug_agente/infrastructure/backup/local_app_data_backup_service.dart';
import 'package:plug_agente/infrastructure/cache/client_token_policy_memory_cache.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/agent_hub_profile_rest_client.dart';
import 'package:plug_agente/infrastructure/external_services/auth_client.dart';
import 'package:plug_agente/infrastructure/external_services/connected_agents_rest_client.dart';
import 'package:plug_agente/infrastructure/external_services/dio_factory.dart';
import 'package:plug_agente/infrastructure/external_services/hub_availability_probe.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_database_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_driver_checker.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/open_cnpj_client.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_client_v2.dart';
import 'package:plug_agente/infrastructure/external_services/transport/open_rpc_document_loader.dart';
import 'package:plug_agente/infrastructure/external_services/via_cep_client.dart';
import 'package:plug_agente/infrastructure/metrics/authorization_cache_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/authorization_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/deprecation_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_native_metrics_service.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/sql_investigation_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool_factory.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_portable_codec.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_repository.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_repository.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/services/auto_start_service.dart';
import 'package:plug_agente/infrastructure/services/http_silent_update_installer.dart';
import 'package:plug_agente/infrastructure/services/noop_notification_service.dart';
import 'package:plug_agente/infrastructure/services/notification_service.dart';
import 'package:plug_agente/infrastructure/stores/agent_action_remote_audit_drift_store.dart';
import 'package:plug_agente/infrastructure/stores/drift_idempotency_store.dart';
import 'package:plug_agente/infrastructure/stores/file_token_audit_store.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_agent_action_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_hub_auth_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_token_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/hub_session_store.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_authorization_decision_cache.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_revoked_token_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_agent_action_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_hub_auth_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_token_audit_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_token_secret_store.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/l10n/agent_action_notification_messages_factory.dart';
import 'package:uuid/uuid.dart';

/// Registers transport, ODBC, auth, and application use-case graph on [getIt].
void registerPlugDependencyGraph(
  GetIt getIt, {
  required odbc.ServiceLocator odbcWorkerLocator,
}) {
  int readPositiveIntEnv(String key, int fallback) {
    final raw = AppEnvironment.get(key);
    if (raw == null || raw.isEmpty) {
      return fallback;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1) {
      return fallback;
    }
    return parsed;
  }

  int readNonNegativeIntEnv(String key, int fallback) {
    final raw = AppEnvironment.get(key);
    if (raw == null || raw.isEmpty) {
      return fallback;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0) {
      return fallback;
    }
    return parsed;
  }

  getIt
    ..registerLazySingleton<odbc.OdbcService>(
      () => odbcWorkerLocator.asyncService,
    )
    ..registerLazySingleton(ConfigValidator.new)
    ..registerLazySingleton(QueryNormalizer.new)
    ..registerLazySingleton(SocketDataSource.new)
    ..registerLazySingleton(
      () => AppDatabase(
        databaseFilePath: getIt<GlobalStorageContext>().databaseFilePath,
      ),
    )
    ..registerLazySingleton<ITokenSecretStore>(
      () {
        try {
          return FlutterSecureTokenSecretStore();
        } on Object catch (e, stackTrace) {
          developer.log(
            'FlutterSecureTokenSecretStore init failed, using NoopTokenSecretStore',
            name: 'plug_dependency_registrar',
            level: 900,
            error: e,
            stackTrace: stackTrace,
          );
          return NoopTokenSecretStore();
        }
      },
    )
    ..registerLazySingleton<IHubAuthSecretStore>(
      () {
        try {
          return FlutterSecureHubAuthSecretStore();
        } on Object catch (e, stackTrace) {
          developer.log(
            'FlutterSecureHubAuthSecretStore init failed, using NoopHubAuthSecretStore',
            name: 'plug_dependency_registrar',
            level: 900,
            error: e,
            stackTrace: stackTrace,
          );
          return NoopHubAuthSecretStore();
        }
      },
    )
    ..registerLazySingleton<IHubSessionStore>(
      () => HubSessionStore(
        getIt<AppDatabase>(),
        authSecretStore: getIt<IHubAuthSecretStore>(),
      ),
    )
    ..registerLazySingleton(
      () => ActiveConfigResolver(
        getIt<IAgentConfigRepository>(),
        getIt<IAppSettingsStore>(),
      ),
    )
    ..registerLazySingleton(
      () => ClientTokenLocalDataSource(
        getIt<AppDatabase>(),
        secretStore: getIt<ITokenSecretStore>(),
      ),
    )
    ..registerLazySingleton(ProtocolNegotiator.new)
    ..registerLazySingleton<IProtocolNegotiator>(getIt.get<ProtocolNegotiator>)
    ..registerLazySingleton(ProtocolMetricsCollector.new)
    ..registerLazySingleton<IProtocolMetricsCollector>(
      getIt.get<ProtocolMetricsCollector>,
    )
    ..registerLazySingleton(AuthorizationMetricsCollector.new)
    ..registerLazySingleton<IAuthorizationMetricsCollector>(
      getIt.get<AuthorizationMetricsCollector>,
    )
    ..registerLazySingleton(DeprecationMetricsCollector.new)
    ..registerLazySingleton<IDeprecationMetricsCollector>(
      getIt.get<DeprecationMetricsCollector>,
    )
    ..registerLazySingleton<IAgentConfigRepository>(
      () => AgentConfigRepository(
        getIt<AppDatabase>(),
        authSecretStore: getIt<IHubAuthSecretStore>(),
        hubSessionStore: getIt<IHubSessionStore>(),
      ),
    )
    ..registerLazySingleton<IAgentActionRepository>(
      () => AgentActionRepository(getIt<AppDatabase>()),
    )
    ..registerLazySingleton(ActionPathValidator.new)
    ..registerLazySingleton(
      () => DeveloperData7ConfigLocator(
        pathValidator: getIt<ActionPathValidator>(),
      ),
    )
    ..registerLazySingleton(DeveloperData7ConnectionCatalog.new)
    ..registerLazySingleton(
      () => DeveloperData7DefinitionResolver(
        pathValidator: getIt<ActionPathValidator>(),
        configLocator: getIt<DeveloperData7ConfigLocator>(),
        connectionCatalog: getIt<DeveloperData7ConnectionCatalog>(),
      ),
    )
    ..registerLazySingleton<IDeveloperData7ConnectionGateway>(
      () => DeveloperData7ConnectionGateway(
        configLocator: getIt<DeveloperData7ConfigLocator>(),
        connectionCatalog: getIt<DeveloperData7ConnectionCatalog>(),
      ),
    )
    ..registerLazySingleton<ComObjectInvocationRegistry>(
      ComObjectInvocationBootstrap.createRegistry,
    )
    ..registerLazySingleton<IComObjectInvocationDiagnostics>(
      () => ComObjectInvocationDiagnostics(getIt<ComObjectInvocationRegistry>()),
    )
    ..registerLazySingleton<ActionCommandSafetyValidator>(() => const ActionCommandSafetyValidator())
    ..registerLazySingleton<IActionCommandSafetyAssessor>(() => getIt<ActionCommandSafetyValidator>())
    ..registerLazySingleton<IAgentActionsBundleFileGateway>(() => const AgentActionsBundleFileGateway())
    ..registerLazySingleton<ActionCommandNormalizer>(
      () => ActionCommandNormalizer(
        commandSafetyValidator: getIt<ActionCommandSafetyValidator>(),
        featureFlags: getIt<FeatureFlags>(),
      ),
    )
    ..registerLazySingleton<AgentActionAdapterRegistry>(
      () => AgentActionAdapterRegistry([
        CommandLineActionAdapter(
          commandNormalizer: getIt<ActionCommandNormalizer>(),
          pathValidator: getIt<ActionPathValidator>(),
        ),
        ExecutableActionAdapter(
          commandNormalizer: getIt<ActionCommandNormalizer>(),
          pathValidator: getIt<ActionPathValidator>(),
        ),
        ScriptActionAdapter(
          commandNormalizer: getIt<ActionCommandNormalizer>(),
          pathValidator: getIt<ActionPathValidator>(),
        ),
        JarActionAdapter(
          commandNormalizer: getIt<ActionCommandNormalizer>(),
          pathValidator: getIt<ActionPathValidator>(),
        ),
        EmailActionAdapter(
          pathValidator: getIt<ActionPathValidator>(),
          secretStore: getIt<IAgentActionSecretStore>(),
        ),
        ComObjectActionAdapter(
          invocationRegistry: getIt<ComObjectInvocationRegistry>(),
          pathValidator: getIt<ActionPathValidator>(),
        ),
        DeveloperData7ActionAdapter(
          definitionResolver: getIt<DeveloperData7DefinitionResolver>(),
        ),
      ]),
    )
    ..registerLazySingleton<CommandLineActionProcessRunner>(
      () => CommandLineActionProcessRunner(
        commandNormalizer: getIt<ActionCommandNormalizer>(),
        pathValidator: getIt<ActionPathValidator>(),
        environmentResolver: getIt<ActionEnvironmentResolver>(),
        operationalProfileResolver: const AgentOperationalProfileResolver(),
      ),
    )
    ..registerLazySingleton<ExecutableActionProcessRunner>(
      () => ExecutableActionProcessRunner(
        commandNormalizer: getIt<ActionCommandNormalizer>(),
        pathValidator: getIt<ActionPathValidator>(),
        environmentResolver: getIt<ActionEnvironmentResolver>(),
      ),
    )
    ..registerLazySingleton<ScriptActionProcessRunner>(
      () => ScriptActionProcessRunner(
        commandNormalizer: getIt<ActionCommandNormalizer>(),
        pathValidator: getIt<ActionPathValidator>(),
        environmentResolver: getIt<ActionEnvironmentResolver>(),
      ),
    )
    ..registerLazySingleton<JarActionProcessRunner>(
      () => JarActionProcessRunner(
        commandNormalizer: getIt<ActionCommandNormalizer>(),
        pathValidator: getIt<ActionPathValidator>(),
        environmentResolver: getIt<ActionEnvironmentResolver>(),
      ),
    )
    ..registerLazySingleton<EmailActionMailerRunner>(
      () => EmailActionMailerRunner(
        pathValidator: getIt<ActionPathValidator>(),
        secretStore: getIt<IAgentActionSecretStore>(),
      ),
    )
    ..registerLazySingleton<ComObjectActionRunner>(
      () => ComObjectActionRunner(
        invocationRegistry: getIt<ComObjectInvocationRegistry>(),
        pathValidator: getIt<ActionPathValidator>(),
      ),
    )
    ..registerLazySingleton<DeveloperData7ProcessRunner>(
      () => DeveloperData7ProcessRunner(
        definitionResolver: getIt<DeveloperData7DefinitionResolver>(),
        environmentResolver: getIt<ActionEnvironmentResolver>(),
        operationalProfileResolver: const AgentOperationalProfileResolver(),
      ),
    )
    ..registerLazySingleton<ActionExecutionQueue>(
      () => ActionExecutionQueue(metrics: getIt<MetricsCollector>()),
    )
    ..registerLazySingleton<IAgentActionSecretStore>(
      () {
        try {
          return FlutterSecureAgentActionSecretStore();
        } on Object catch (e, stackTrace) {
          developer.log(
            'FlutterSecureAgentActionSecretStore init failed, using NoopAgentActionSecretStore',
            name: 'plug_dependency_registrar',
            level: 900,
            error: e,
            stackTrace: stackTrace,
          );
          return const NoopAgentActionSecretStore();
        }
      },
    )
    ..registerLazySingleton(
      () => AgentActionSecretPlaceholderResolver(
        secretStore: getIt<IAgentActionSecretStore>(),
      ),
    )
    ..registerLazySingleton(
      () => ActionEnvironmentResolver(
        secretPlaceholderResolver: getIt<AgentActionSecretPlaceholderResolver>(),
      ),
    )
    ..registerLazySingleton(
      () => SaveAgentActionSecret(getIt<IAgentActionSecretStore>()),
    )
    ..registerLazySingleton(
      () => DeleteAgentActionSecret(getIt<IAgentActionSecretStore>()),
    )
    ..registerLazySingleton<AgentActionRuntimeRequestValidator>(
      AgentActionRuntimeRequestValidator.new,
    )
    ..registerLazySingleton<AgentActionDefinitionSnapshotter>(
      AgentActionDefinitionSnapshotter.new,
    )
    ..registerLazySingleton(
      () => AgentActionSecretReferenceFingerprinter(getIt<IAgentActionSecretStore>()),
    )
    ..registerLazySingleton<AgentActionRuntimeStateGuard>(
      () => AgentActionRuntimeStateGuard(getIt<FeatureFlags>()),
    )
    ..registerLazySingleton(ElevatedActionRunnerReadinessService.new)
    ..registerLazySingleton<IAgentActionsRemoteCapabilityProvider>(
      () => AgentActionsRemoteCapabilityProvider(
        runtimeStateGuard: getIt<AgentActionRuntimeStateGuard>(),
        elevatedRunnerReadiness: getIt<ElevatedActionRunnerReadinessService>(),
      ),
    )
    ..registerLazySingleton(ElevatedActionExecutionAbortRegistry.new)
    ..registerLazySingleton(
      () => ElevatedActionRunnerInstaller(
        storageContext: getIt<GlobalStorageContext>(),
      ),
    )
    ..registerLazySingleton(
      () => PrepareElevatedActionRunner(
        getIt<ElevatedActionRunnerInstaller>(),
        getIt<ElevatedActionRunnerReadinessService>(),
        getIt<GlobalStorageContext>(),
      ),
    )
    ..registerLazySingleton(
      () => ElevatedActionRequestProtector(
        storageContext: getIt<GlobalStorageContext>(),
      ),
    )
    ..registerLazySingleton(
      () => ElevatedActionExecutionMaterializer(
        storageContext: getIt<GlobalStorageContext>(),
      ),
    )
    ..registerLazySingleton<IElevatedActionRunnerBridge>(
      () => ElevatedActionRunnerBridge(
        requestProtector: getIt<ElevatedActionRequestProtector>(),
        materializer: getIt<ElevatedActionExecutionMaterializer>(),
      ),
    )
    ..registerLazySingleton(
      () => ElevatedActionStatusFileSyncer(
        storageContext: getIt<GlobalStorageContext>(),
        metrics: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => ElevatedActionStatusFileWriter(
        storageContext: getIt<GlobalStorageContext>(),
      ),
    )
    ..registerLazySingleton<IElevatedActionExecutionCanceller>(
      () => ElevatedActionExecutionCanceller(
        storageContext: getIt<GlobalStorageContext>(),
        statusFileWriter: getIt<ElevatedActionStatusFileWriter>(),
      ),
    )
    ..registerLazySingleton(
      () => ElevatedAgentActionExecutionService(
        bridge: getIt<IElevatedActionRunnerBridge>(),
        statusFileSyncer: getIt<ElevatedActionStatusFileSyncer>(),
        readiness: getIt<ElevatedActionRunnerReadinessService>(),
        abortRegistry: getIt<ElevatedActionExecutionAbortRegistry>(),
      ),
    )
    ..registerLazySingleton<AgentActionLocalRunnerRegistry>(
      () => AgentActionLocalRunnerRegistry([
        getIt<CommandLineActionProcessRunner>(),
        getIt<ExecutableActionProcessRunner>(),
        getIt<ScriptActionProcessRunner>(),
        getIt<JarActionProcessRunner>(),
        getIt<EmailActionMailerRunner>(),
        getIt<ComObjectActionRunner>(),
        getIt<DeveloperData7ProcessRunner>(),
      ]),
    )
    ..registerLazySingleton(
      () => AgentRegisterProfileProvider(
        activeConfigResolver: getIt<ActiveConfigResolver>(),
      ),
    )
    ..registerLazySingleton(() => const Uuid())
    ..registerLazySingleton<IConnectionPool>(
      () => createOdbcConnectionPool(
        getIt<odbc.OdbcService>(),
        getIt<IOdbcConnectionSettings>(),
        getIt<MetricsCollector>(),
        getIt<FeatureFlags>(),
        getIt<ActiveConfigResolver>(),
      ),
    )
    ..registerLazySingleton<IRetryManager>(RetryManager.new)
    ..registerLazySingleton<SqlInvestigationCollector>(SqlInvestigationCollector.new)
    ..registerLazySingleton<ISqlInvestigationCollector>(getIt.get<SqlInvestigationCollector>)
    ..registerLazySingleton(MetricsCollector.new)
    ..registerLazySingleton<AgentActionRetentionSettings>(
      () => AgentActionRetentionSettings(getIt<IAppSettingsStore>()),
    )
    ..registerLazySingleton<AgentActionPreflightSettings>(
      () => AgentActionPreflightSettings(getIt<IAppSettingsStore>()),
    )
    ..registerLazySingleton(
      () => HealthService(
        metricsCollector: getIt<MetricsCollector>(),
        gateway: getIt<IDatabaseGateway>(),
        odbcSettings: getIt<IOdbcConnectionSettings>(),
        connectionPool: getIt<IConnectionPool>(),
        activeConfigResolver: getIt<ActiveConfigResolver>(),
        streamingGateway: getIt<IStreamingDatabaseGateway>(),
        directConnectionLimiter: getIt<DirectOdbcConnectionLimiter>(),
        featureFlags: getIt<FeatureFlags>(),
        odbcRuntimeTuning: getIt<OdbcRuntimeTuning>(),
        agentRuntimeIdentity: getIt<AgentRuntimeIdentity>(),
        agentActionRunnerRegistry: getIt<AgentActionLocalRunnerRegistry>(),
        agentActionRuntimeStateGuard: getIt<AgentActionRuntimeStateGuard>(),
        elevatedRunnerReadiness: getIt<ElevatedActionRunnerReadinessService>(),
        agentActionRetentionSettings: getIt<AgentActionRetentionSettings>(),
        agentActionTriggerScheduler: getIt.isRegistered<AgentActionTriggerScheduler>()
            ? getIt<AgentActionTriggerScheduler>()
            : null,
        agentActionSchedulerInstanceLock: getIt.isRegistered<IAgentActionSchedulerInstanceLock>()
            ? getIt<IAgentActionSchedulerInstanceLock>()
            : null,
        comObjectInvocationDiagnostics: getIt<IComObjectInvocationDiagnostics>(),
      ),
    )
    ..registerLazySingleton(
      () => DirectOdbcConnectionLimiter(
        maxConcurrent: ConnectionConstants.directOdbcConnectionConcurrency(
          getIt<IOdbcConnectionSettings>().poolSize,
        ),
        acquireTimeout: ConnectionConstants.defaultPoolAcquireTimeout,
        metricsCollector: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => OdbcNativeMetricsService(
        getIt<odbc.OdbcService>(),
        activeConfigResolver: getIt<ActiveConfigResolver>(),
        connectionPool: getIt<IConnectionPool>(),
        settings: getIt<IOdbcConnectionSettings>(),
        runtimeTuning: getIt<OdbcRuntimeTuning>(),
        metricsCollector: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton<IMetricsCollector>(getIt.get<MetricsCollector>)
    ..registerLazySingleton<IRpcDispatchMetricsCollector>(
      () => RpcDispatchMetricsCollector(getIt<MetricsCollector>()),
    )
    ..registerLazySingleton(
      () => ClientTokenGetPolicyRateLimiter(
        maxCallsPerMinute: readNonNegativeIntEnv(
          'CLIENT_TOKEN_GET_POLICY_MAX_PER_MINUTE',
          ConnectionConstants.clientTokenGetPolicyDefaultMaxPerMinute,
        ),
        maxScopeEntries: readNonNegativeIntEnv(
          'CLIENT_TOKEN_GET_POLICY_MAX_SCOPE_KEYS',
          ConnectionConstants.clientTokenGetPolicyDefaultMaxScopeKeys,
        ),
      ),
    )
    ..registerLazySingleton(
      () => AgentActionRemoteRateLimiter(
        maxCallsPerMinute: readNonNegativeIntEnv(
          'AGENT_ACTION_REMOTE_MAX_PER_MINUTE',
          0,
        ),
        maxScopeEntries: readNonNegativeIntEnv(
          'AGENT_ACTION_REMOTE_MAX_SCOPE_KEYS',
          8192,
        ),
      ),
    )
    ..registerLazySingleton(
      () => AgentActionRemoteLifecycleAuditRecorder(
        featureFlags: getIt<FeatureFlags>(),
        auditStore: getIt<IAgentActionRemoteAuditStore>(),
        runtimeIdentity: getIt<AgentRuntimeIdentity>(),
        uuid: getIt<Uuid>(),
      ),
    )
    ..registerLazySingleton<IAuthorizationCacheMetrics>(
      () => AuthorizationCacheMetricsCollector(getIt<MetricsCollector>()),
    )
    ..registerLazySingleton<IIdempotencyStore>(
      () => DriftIdempotencyStore(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<IAuthorizationDecisionCache>(
      () => InMemoryAuthorizationDecisionCache(
        maxEntries: readPositiveIntEnv(
          'AUTH_DECISION_CACHE_MAX_ENTRIES',
          8192,
        ),
      ),
    )
    ..registerLazySingleton<IClientTokenPolicyCache>(
      () => ClientTokenPolicyMemoryCache(
        maxEntries: readPositiveIntEnv(
          'AUTH_POLICY_CACHE_MAX_ENTRIES',
          2048,
        ),
      ),
    )
    ..registerLazySingleton<IRevokedTokenStore>(InMemoryRevokedTokenStore.new)
    ..registerLazySingleton<ITokenAuditStore>(
      () => getIt<FeatureFlags>().enableTokenAudit ? FileTokenAuditStore() : NoopTokenAuditStore(),
    )
    ..registerLazySingleton<IAgentActionRemoteAuditStore>(
      () => AgentActionRemoteAuditDriftStore(getIt<AppDatabase>()),
    )
    ..registerLazySingleton(
      () => AgentActionRemoteAuthorizationService(
        featureFlags: getIt<FeatureFlags>(),
        getClientTokenPolicy: getIt<GetClientTokenPolicy>(),
        authorizeSqlOperation: getIt<AuthorizeSqlOperation>(),
        authorizationStageBudget: const Duration(seconds: 3),
        onPermissionDenied: getIt<MetricsCollector>().recordRemotePermissionDenied,
      ),
    )
    ..registerLazySingleton(OpenRpcDocumentLoader.new)
    ..registerLazySingleton(
      () => RpcMethodDispatcher(
        databaseGateway: getIt<IDatabaseGateway>(),
        healthService: getIt<HealthService>(),
        normalizerService: getIt<QueryNormalizerService>(),
        uuid: getIt<Uuid>(),
        authorizeSqlOperation: getIt<AuthorizeSqlOperation>(),
        getClientTokenPolicy: getIt<GetClientTokenPolicy>(),
        getPolicyRateLimiter: getIt<ClientTokenGetPolicyRateLimiter>(),
        featureFlags: getIt<FeatureFlags>(),
        activeConfigResolver: getIt<ActiveConfigResolver>(),
        idempotencyStore: getIt<IIdempotencyStore>(),
        authMetrics: getIt<IAuthorizationMetricsCollector>(),
        deprecationMetrics: getIt<IDeprecationMetricsCollector>(),
        dispatchMetrics: getIt<IRpcDispatchMetricsCollector>(),
        onIdempotencyFingerprintMismatch: getIt<MetricsCollector>().recordIdempotencyFingerprintMismatch,
        onAgentActionRemoteAuditExecutionCorrelated: getIt<MetricsCollector>().recordRemoteAuditExecutionCorrelated,
        onAgentActionRemoteRateLimited: getIt<MetricsCollector>().recordRemoteRateLimited,
        sqlInvestigation: getIt<ISqlInvestigationCollector>(),
        streamingGateway: getIt<IStreamingDatabaseGateway>(),
        odbcNativeMetricsService: getIt<OdbcNativeMetricsService>(),
        runAgentActionLocally: getIt<RunAgentActionLocally>(),
        runAgentActionViaRemoteTrigger: getIt<RunAgentActionViaRemoteTrigger>(),
        cancelAgentActionExecution: getIt<CancelAgentActionExecution>(),
        getAgentActionExecution: getIt<GetAgentActionExecution>(),
        sliceAgentActionCapturedOutput: getIt<SliceAgentActionCapturedOutput>(),
        getAgentActionDefinition: getIt<GetAgentActionDefinition>(),
        backfillAgentActionExecutionCorrelation: getIt<BackfillAgentActionExecutionCorrelation>(),
        agentActionRemoteRateLimiter: getIt<AgentActionRemoteRateLimiter>(),
        agentActionRemoteAuthorization: getIt<AgentActionRemoteAuthorizationService>(),
        agentActionRemoteAuditStore: getIt<IAgentActionRemoteAuditStore>(),
        agentActionRuntimeStateGuard: getIt<AgentActionRuntimeStateGuard>(),
        agentRuntimeIdentity: getIt<AgentRuntimeIdentity>(),
        agentActionRetentionSettings: getIt<AgentActionRetentionSettings>(),
        loadOpenRpcDocument: getIt<OpenRpcDocumentLoader>().getDocument,
      ),
    )
    ..registerLazySingleton<IRpcRequestDispatcher>(
      getIt.get<RpcMethodDispatcher>,
    )
    ..registerLazySingleton<ITransportClient>(
      () {
        PayloadSigningConfig environmentSigningConfig() {
          final signingKey = AppEnvironment.get('PAYLOAD_SIGNING_KEY');
          final signingKeyId = AppEnvironment.get('PAYLOAD_SIGNING_KEY_ID');
          return PayloadSigningConfig(
            activeKeyId: signingKeyId,
            keys: {
              if (signingKeyId != null && signingKey != null) signingKeyId: signingKey,
            },
            source: PayloadSigningConfigSource.environment,
          );
        }

        final signingConfig = getIt.isRegistered<PayloadSigningConfig>()
            ? getIt<PayloadSigningConfig>()
            : environmentSigningConfig();
        PayloadSigner? payloadSigner;
        if (signingConfig.hasConfiguredSigner) {
          payloadSigner = PayloadSigner(
            keys: signingConfig.keys,
            activeKeyId: signingConfig.activeKeyId,
          );
          developer.log(
            'PayloadFrame signer configured '
            '(active_key_id=${payloadSigner.activeKeyId}, key_count=${payloadSigner.keyCount}, '
            'source=${signingConfig.sourceName})',
            name: 'plug_dependency_registrar',
            level: 800,
          );
        }
        for (final warning in signingConfig.warnings) {
          developer.log(
            'PayloadFrame signing configuration warning: $warning',
            name: 'plug_dependency_registrar',
            level: 900,
          );
        }
        return SocketIOTransportClientV2(
          dataSource: getIt<SocketDataSource>(),
          negotiator: getIt<IProtocolNegotiator>(),
          rpcDispatcher: getIt<IRpcRequestDispatcher>(),
          featureFlags: getIt<FeatureFlags>(),
          options: SocketIOTransportClientV2Options(
            payloadSigner: payloadSigner,
            payloadSigningConfig: signingConfig,
            protocolMetricsCollector: getIt<ProtocolMetricsCollector>(),
            metricsCollector: getIt<MetricsCollector>(),
            agentActionsRemoteCapabilityProvider: getIt<IAgentActionsRemoteCapabilityProvider>(),
            agentActionLocalRunnerRegistry: getIt<AgentActionLocalRunnerRegistry>(),
            registerProfileProvider: getIt<AgentRegisterProfileProvider>().loadSnapshot,
            jsonSchemaValidator: getIt.isRegistered<JsonSchemaContractValidator>()
                ? getIt<JsonSchemaContractValidator>()
                : null,
          ),
        );
      },
    )
    ..registerLazySingleton<IDatabaseGateway>(
      () {
        // Create base ODBC gateway
        final baseGateway = OdbcDatabaseGateway(
          getIt<ActiveConfigResolver>(),
          getIt<odbc.OdbcService>(),
          getIt<IConnectionPool>(),
          getIt<IRetryManager>(),
          getIt<MetricsCollector>(),
          getIt<IOdbcConnectionSettings>(),
          featureFlags: getIt<FeatureFlags>(),
          directConnectionLimiter: getIt<DirectOdbcConnectionLimiter>(),
          sqlInvestigation: getIt<ISqlInvestigationCollector>(),
        );

        // Wrap with SQL execution queue for backpressure control
        final sqlQueueMaxWorkers = ConnectionConstants.sqlQueueMaxWorkersForPoolSize(
          getIt<IOdbcConnectionSettings>().poolSize,
        );
        final persistedPoolSize = getIt<IOdbcConnectionSettings>().poolSize;
        if (sqlQueueMaxWorkers == persistedPoolSize) {
          getIt<MetricsCollector>().recordSqlQueueWorkersEqualPool(
            workers: sqlQueueMaxWorkers,
            poolSize: persistedPoolSize,
          );
        }
        final sqlQueue = SqlExecutionQueue(
          maxQueueSize: ConnectionConstants.sqlQueueMaxSize,
          maxConcurrentWorkers: sqlQueueMaxWorkers,
          metricsCollector: getIt<MetricsCollector>(),
          defaultEnqueueTimeout: ConnectionConstants.sqlQueueEnqueueTimeout,
        );

        developer.log(
          'SQL queue initialized: maxSize=${ConnectionConstants.sqlQueueMaxSize}, '
          'maxWorkers=$sqlQueueMaxWorkers',
          name: 'plug_dependency_registrar',
          level: 800,
        );

        return QueuedDatabaseGateway(
          delegate: baseGateway,
          queue: sqlQueue,
        );
      },
    )
    ..registerLazySingleton<IStreamingDatabaseGateway>(
      () => OdbcStreamingGateway(
        getIt<odbc.OdbcService>(),
        getIt<IOdbcConnectionSettings>(),
        directConnectionLimiter: getIt<DirectOdbcConnectionLimiter>(),
        metricsCollector: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton<IOdbcDriverChecker>(OdbcDriverChecker.new)
    ..registerLazySingleton<IAuthClient>(
      () => AuthClient(DioFactory.createDio()),
    )
    ..registerLazySingleton<IConnectedAgentsGateway>(
      () => ConnectedAgentsRestClient(
        DioFactory.createDio(
          requestTimeout: ConnectionConstants.backupRestoreAgentsListTimeout,
        ),
      ),
    )
    ..registerLazySingleton<ILocalAppDataBackupService>(
      () => LocalAppDataBackupService(
        database: getIt<AppDatabase>(),
        storageContext: getIt<GlobalStorageContext>(),
        settingsStore: getIt<IAppSettingsStore>(),
        authClient: getIt<IAuthClient>(),
        connectedAgentsGateway: getIt<IConnectedAgentsGateway>(),
      ),
    )
    ..registerLazySingleton<IHubAvailabilityProbe>(
      () {
        final probePath = AppEnvironment.get('HUB_AVAILABILITY_PROBE_PATH');
        return HubAvailabilityProbe(
          probePath: (probePath != null && probePath.isNotEmpty)
              ? probePath
              : AppConstants.defaultHubAvailabilityProbePath,
        );
      },
    )
    ..registerLazySingleton<IAgentHubProfileGateway>(
      () => AgentHubProfileRestClient(DioFactory.createDio()),
    )
    ..registerLazySingleton(
      () => ViaCepClient(
        DioFactory.createDio(
          requestTimeout: const Duration(
            seconds: AppConstants.publicApiTimeoutSeconds,
          ),
        ),
      ),
    )
    ..registerLazySingleton(
      () => OpenCnpjClient(
        DioFactory.createDio(
          requestTimeout: const Duration(
            seconds: AppConstants.publicApiTimeoutSeconds,
          ),
        ),
      ),
    )
    ..registerLazySingleton<IOpenCnpjLookup>(() => getIt<OpenCnpjClient>())
    ..registerLazySingleton<IViaCepLookup>(() => getIt<ViaCepClient>())
    ..registerLazySingleton(() => LookupAgentCnpj(getIt<IOpenCnpjLookup>()))
    ..registerLazySingleton(() => LookupAgentCep(getIt<IViaCepLookup>()))
    ..registerLazySingleton<IAuthorizationPolicyResolver>(
      () => AuthorizationPolicyResolver(
        getIt<FeatureFlags>(),
        jwksVerifier: getIt<JwtJwksVerifier>(),
        localDataSource: getIt<ClientTokenLocalDataSource>(),
        revokedTokenStore: getIt<IRevokedTokenStore>(),
        tokenAuditStore: getIt<ITokenAuditStore>(),
        policyCache: getIt<IClientTokenPolicyCache>(),
        cacheMetrics: getIt<IAuthorizationCacheMetrics>(),
      ),
    )
    ..registerLazySingleton(
      () => GetClientTokenPolicy(getIt<IAuthorizationPolicyResolver>()),
    )
    ..registerLazySingleton<JwtJwksVerifier>(
      () => JwtJwksVerifier(() async {
        final jwksUrlOverride = AppEnvironment.get('JWKS_URL');
        if (jwksUrlOverride != null && jwksUrlOverride.isNotEmpty) {
          return JwksConfig(
            jwksUrl: jwksUrlOverride,
            issuer: AppEnvironment.get('JWKS_ISSUER'),
            audience: AppEnvironment.get('JWKS_AUDIENCE'),
          );
        }
        final configResult = await getIt<ActiveConfigResolver>().resolveActiveOrFallback(
          metadataOnly: true,
        );
        return configResult.fold(
          (config) {
            final base = config.serverUrl.trim();
            if (base.isEmpty) return null;
            final normalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
            return JwksConfig(
              jwksUrl: '$normalized/.well-known/jwks.json',
              issuer: AppEnvironment.get('JWKS_ISSUER'),
              audience: AppEnvironment.get('JWKS_AUDIENCE'),
            );
          },
          (_) => null,
        );
      }),
    )
    ..registerLazySingleton<IClientTokenRepository>(
      () => ClientTokenRepository(getIt<ClientTokenLocalDataSource>()),
    )
    ..registerLazySingleton(
      () => ConnectionService(
        getIt.call<ITransportClient>,
        getIt<IDatabaseGateway>(),
      ),
    )
    ..registerLazySingleton(
      () => AuthService(getIt<IAuthClient>(), getIt<IHubSessionStore>()),
    )
    ..registerLazySingleton(
      () => HubSessionCoordinator(
        getIt<ActiveConfigResolver>(),
        getIt<LoginUser>(),
        getIt<RefreshAuthToken>(),
        getIt<SaveAuthToken>(),
        getIt<IHubSessionStore>(),
      ),
    )
    ..registerLazySingleton(
      () => QueryNormalizerService(getIt<QueryNormalizer>()),
    )
    ..registerLazySingleton(
      SqlOperationClassifier.new,
    )
    ..registerLazySingleton(
      () => ClientTokenValidationService(getIt<IAuthorizationPolicyResolver>()),
    )
    ..registerLazySingleton(() => ConfigService(getIt<ConfigValidator>()))
    ..registerLazySingleton(() => ConnectToHub(getIt<ConnectionService>()))
    ..registerLazySingleton(
      () => TestDbConnection(getIt<ConnectionService>()),
    )
    ..registerLazySingleton(
      () => CheckOdbcDriver(getIt<IOdbcDriverChecker>()),
    )
    ..registerLazySingleton(
      () => CheckHubAvailability(getIt<IHubAvailabilityProbe>()),
    )
    ..registerLazySingleton(
      () => ExecutePlaygroundQuery(
        getIt<IDatabaseGateway>(),
        getIt<ActiveConfigResolver>(),
        getIt<Uuid>(),
      ),
    )
    ..registerLazySingleton(
      () => ExecuteStreamingQuery(
        getIt<IStreamingDatabaseGateway>(),
        getIt<IOdbcConnectionSettings>(),
      ),
    )
    ..registerLazySingleton(
      () => SaveAgentConfig(
        getIt<IAgentConfigRepository>(),
        getIt<ConfigService>(),
      ),
    )
    ..registerLazySingleton(
      () => LoadAgentConfig(getIt<ActiveConfigResolver>()),
    )
    ..registerLazySingleton(
      () => ValidateAgentActionDefinition(
        getIt<AgentActionAdapterRegistry>(),
        secretPlaceholderResolver: getIt<AgentActionSecretPlaceholderResolver>(),
        runtimeExecutionValidator: const AgentActionRuntimeExecutionValidator(),
        environmentResolver: getIt<ActionEnvironmentResolver>(),
      ),
    )
    ..registerLazySingleton(
      () => TestAgentActionDefinition(
        getIt<IAgentActionRepository>(),
        getIt<ValidateAgentActionDefinition>(),
      ),
    )
    ..registerLazySingleton(
      () => PreviewAgentActionDefinition(
        getIt<IAgentActionRepository>(),
        getIt<AgentActionAdapterRegistry>(),
      ),
    )
    ..registerLazySingleton(
      () => SaveAgentActionDefinition(
        getIt<IAgentActionRepository>(),
        getIt<ValidateAgentActionDefinition>(),
        getIt<AgentActionDefinitionSnapshotter>(),
        getIt<FeatureFlags>(),
        secretReferenceFingerprinter: getIt<AgentActionSecretReferenceFingerprinter>(),
        preflightSettings: getIt<AgentActionPreflightSettings>(),
      ),
    )
    ..registerLazySingleton(
      () => GetAgentActionDefinition(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => ListAgentActionDefinitions(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => ListDeveloperData7Connections(
        getIt<IDeveloperData7ConnectionGateway>(),
      ),
    )
    ..registerLazySingleton(
      () => DeleteAgentActionDefinition(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      ValidateAgentActionTrigger.new,
    )
    ..registerLazySingleton(
      () => SaveAgentActionTrigger(
        getIt<IAgentActionRepository>(),
        getIt<ValidateAgentActionTrigger>(),
        getIt<FeatureFlags>(),
      ),
    )
    ..registerLazySingleton(
      () => GetAgentActionTrigger(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => ListAgentActionTriggers(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton<IAgentActionPortableCodec>(
      AgentActionPortableCodec.new,
    )
    ..registerLazySingleton(
      () => AgentActionBackupSanitizer(codec: getIt<IAgentActionPortableCodec>()),
    )
    ..registerLazySingleton(
      () => ExportAgentActionsBundle(
        getIt<ListAgentActionDefinitions>(),
        getIt<ListAgentActionTriggers>(),
        getIt<AgentActionBackupSanitizer>(),
      ),
    )
    ..registerLazySingleton(
      () => ImportAgentActionsBundle(
        getIt<SaveAgentActionDefinition>(),
        getIt<SaveAgentActionTrigger>(),
        getIt<AgentActionBackupSanitizer>(),
      ),
    )
    ..registerLazySingleton(
      () => DeleteAgentActionTrigger(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => SaveAgentActionExecution(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => GetAgentActionExecution(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton<SliceAgentActionCapturedOutput>(
      () => SliceAgentActionCapturedOutput(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => BackfillAgentActionExecutionCorrelation(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => ListAgentActionExecutions(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => ListRecentAgentActionRemoteAudit(getIt<IAgentActionRemoteAuditStore>()),
    )
    ..registerLazySingleton(
      () => CleanupExpiredRpcIdempotencyCache(
        getIt<IIdempotencyStore>(),
        metrics: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => RpcIdempotencyCachePeriodicPurge(
        ({DateTime? referenceTime}) => getIt<CleanupExpiredRpcIdempotencyCache>()(referenceTime: referenceTime),
      ),
    )
    ..registerLazySingleton(
      () => CleanupExpiredAgentActionRemoteAudit(
        getIt<IAgentActionRemoteAuditStore>(),
        retention: getIt<AgentActionRetentionSettings>().remoteAuditRetention,
        metrics: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => AgentActionRemoteAuditPeriodicPurge(
        ({DateTime? referenceTime}) => getIt<CleanupExpiredAgentActionRemoteAudit>()(referenceTime: referenceTime),
      ),
    )
    ..registerLazySingleton(
      () => CleanupExpiredElevatedBridgeArtifacts(
        storageContext: getIt<GlobalStorageContext>(),
        metrics: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => ElevatedBridgeArtifactsPeriodicPurge(
        ({DateTime? referenceTime}) => getIt<CleanupExpiredElevatedBridgeArtifacts>()(referenceTime: referenceTime),
      ),
    )
    ..registerLazySingleton(
      () => CleanupAgentActionCapturedOutput(
        getIt<IAgentActionRepository>(),
        retention: getIt<AgentActionRetentionSettings>().capturedOutputRetention,
        metrics: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => AgentActionCapturedOutputPeriodicPurge(
        ({DateTime? now}) => getIt<CleanupAgentActionCapturedOutput>()(now: now),
      ),
    )
    ..registerLazySingleton(
      () => CleanupAgentActionExecutions(
        getIt<IAgentActionRepository>(),
        retention: getIt<AgentActionRetentionSettings>().executionRetention,
        metrics: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => AgentActionExecutionPeriodicPurge(
        ({DateTime? referenceTime}) => getIt<CleanupAgentActionExecutions>()(now: referenceTime),
      ),
    )
    ..registerLazySingleton<IAgentActionOrphanProcessTerminator>(
      () => const AgentActionOrphanProcessTerminator(),
    )
    ..registerLazySingleton(
      () => ReconcileAgentActionExecutions(
        getIt<IAgentActionRepository>(),
        saveExecution: getIt<SaveAgentActionExecution>(),
        orphanProcessTerminator: getIt<IAgentActionOrphanProcessTerminator>(),
      ),
    )
    ..registerLazySingleton(
      () => ApplyAgentActionOnAppExitPolicies(
        getIt<IAgentActionRepository>(),
        getIt<CancelAgentActionExecution>(),
      ),
    )
    ..registerLazySingleton(
      () => CancelAgentActionExecution(
        getIt<IAgentActionRepository>(),
        getIt<AgentActionLocalRunnerRegistry>(),
        executionQueue: getIt<ActionExecutionQueue>(),
        saveExecution: getIt<SaveAgentActionExecution>(),
        metrics: getIt<MetricsCollector>(),
        elevatedCanceller: getIt<IElevatedActionExecutionCanceller>(),
        elevatedAbortRegistry: getIt<ElevatedActionExecutionAbortRegistry>(),
        remoteLifecycleAudit: getIt<AgentActionRemoteLifecycleAuditRecorder>(),
      ),
    )
    ..registerLazySingleton(
      () => RunAgentActionLocally(
        getIt<IAgentActionRepository>(),
        getIt<AgentActionLocalRunnerRegistry>(),
        getIt<Uuid>(),
        executionQueue: getIt<ActionExecutionQueue>(),
        runtimeRequestValidator: getIt<AgentActionRuntimeRequestValidator>(),
        runtimeExecutionValidator: const AgentActionRuntimeExecutionValidator(),
        runtimeStateGuard: getIt<AgentActionRuntimeStateGuard>(),
        featureFlags: getIt<FeatureFlags>(),
        saveExecution: getIt<SaveAgentActionExecution>(),
        runtimeIdentity: getIt<AgentRuntimeIdentity>(),
        metrics: getIt<MetricsCollector>(),
        operationalProfileResolver: const AgentOperationalProfileResolver(),
        notifyExecution: NotifyAgentActionExecutionIfConfigured(
          getIt<SendNotification>(),
          resolveMessages: agentActionNotificationMessagesForPlatformLocale,
          notificationsSupported: () => getIt<RuntimeCapabilities>().supportsNotifications,
        ),
        secretPlaceholderResolver: getIt<AgentActionSecretPlaceholderResolver>(),
        adapterRegistry: getIt<AgentActionAdapterRegistry>(),
        elevatedRunnerReadiness: getIt<ElevatedActionRunnerReadinessService>(),
        elevatedExecutionService: getIt<ElevatedAgentActionExecutionService>(),
        remoteLifecycleAudit: getIt<AgentActionRemoteLifecycleAuditRecorder>(),
        definitionSnapshotter: getIt<AgentActionDefinitionSnapshotter>(),
        secretReferenceFingerprinter: getIt<AgentActionSecretReferenceFingerprinter>(),
      ),
    )
    ..registerLazySingleton(
      () => DispatchAgentActionTrigger(
        getIt<IAgentActionRepository>(),
        getIt<RunAgentActionLocally>(),
      ),
    )
    ..registerLazySingleton(
      () => RunAgentActionViaRemoteTrigger(
        getIt<IAgentActionRepository>(),
        getIt<DispatchAgentActionTrigger>(),
      ),
    )
    ..registerLazySingleton<IAgentActionSchedulerInstanceLock>(
      () => AgentActionSchedulerInstanceLock(
        storageContext: getIt<GlobalStorageContext>(),
        runtimeIdentity: getIt<AgentRuntimeIdentity>(),
      ),
    )
    ..registerLazySingleton(
      () => AgentActionTriggerScheduler(
        getIt<IAgentActionRepository>(),
        getIt<DispatchAgentActionTrigger>(),
        featureFlags: getIt<FeatureFlags>(),
        schedulerInstanceLock: getIt<IAgentActionSchedulerInstanceLock>(),
      ),
    )
    ..registerLazySingleton(
      () => AgentActionSubsystemCoordinator(
        getIt<AgentActionRuntimeStateGuard>(),
        getIt<AgentActionTriggerScheduler>(),
        getIt<FeatureFlags>(),
      ),
    )
    ..registerLazySingleton<ISilentUpdateInstaller>(
      () => HttpSilentUpdateInstaller(
        downloadTimeout: Duration(
          seconds: resolveAutoUpdateDownloadTimeoutSeconds(
            environment: AppEnvironment.snapshot(),
          ),
        ),
      ),
    )
    ..registerLazySingleton<IAutoUpdateOrchestrator>(
      () => AutoUpdateOrchestrator(
        getIt<RuntimeCapabilities>(),
        silentUpdateInstaller: getIt<ISilentUpdateInstaller>(),
        settingsStore: getIt<IAppSettingsStore>(),
        metricsCollector: getIt<MetricsCollector>(),
        helperWaitDuration: Duration(
          minutes: resolveAutoUpdateHelperWaitMinutes(
            environment: AppEnvironment.snapshot(),
          ),
        ),
        automaticBootJitterProvider: _autoUpdateBootJitter,
        closeApplicationForSilentUpdate: _closeApplicationForSilentUpdate,
        allowQuitForUpdate: () async {
          if (getIt.isRegistered<WindowManagerService>()) {
            await getIt<WindowManagerService>().allowQuitForUpdate();
          }
        },
      ),
    )
    ..registerLazySingleton(
      () => PushAgentProfileToHub(
        getIt<IAgentHubProfileGateway>(),
        getIt<Uuid>(),
      ),
    )
    ..registerLazySingleton(() => LoginUser(getIt<AuthService>()))
    ..registerLazySingleton(() => RefreshAuthToken(getIt<AuthService>()))
    ..registerLazySingleton(() => SaveAuthToken(getIt<AuthService>()))
    ..registerLazySingleton(
      () => CreateClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
      ),
    )
    ..registerLazySingleton(
      () => ListClientTokens(getIt<IClientTokenRepository>()),
    )
    ..registerLazySingleton(
      () => GetClientTokenSecret(getIt<IClientTokenRepository>()),
    )
    ..registerLazySingleton(
      () => UpdateClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
        decisionCache: getIt<IAuthorizationDecisionCache>(),
        policyCache: getIt<IClientTokenPolicyCache>(),
      ),
    )
    ..registerLazySingleton(
      () => RevokeClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
        decisionCache: getIt<IAuthorizationDecisionCache>(),
        policyCache: getIt<IClientTokenPolicyCache>(),
      ),
    )
    ..registerLazySingleton(
      () => DeleteClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
        decisionCache: getIt<IAuthorizationDecisionCache>(),
        policyCache: getIt<IClientTokenPolicyCache>(),
      ),
    )
    ..registerLazySingleton(
      () => AuthorizeSqlOperation(
        getIt<SqlOperationClassifier>(),
        getIt<ClientTokenValidationService>(),
        decisionCache: getIt<IAuthorizationDecisionCache>(),
        cacheMetrics: getIt<IAuthorizationCacheMetrics>(),
      ),
    );
}

/// Tray, startup, notification services and notification use cases.
void registerPlugCapabilityServices(
  GetIt getIt,
  RuntimeCapabilities capabilities,
) {
  if (capabilities.supportsTray) {
    developer.log(
      'Registering TrayManagerService',
      name: 'plug_dependency_registrar',
    );
    getIt.registerLazySingleton<ITrayService>(TrayManagerService.new);
  } else {
    developer.log(
      'Registering NoopTrayManagerService (degraded mode)',
      name: 'plug_dependency_registrar',
    );
    getIt.registerLazySingleton<ITrayService>(
      NoopTrayManagerService.new,
    );
  }

  if (capabilities.supportsWindowManager) {
    developer.log(
      'Registering AutoStartService',
      name: 'plug_dependency_registrar',
    );
    getIt.registerLazySingleton<IStartupService>(
      AutoStartService.new,
    );
  }

  if (capabilities.supportsNotifications) {
    developer.log(
      'Registering NotificationService',
      name: 'plug_dependency_registrar',
    );
    getIt.registerLazySingleton<INotificationService>(NotificationService.new);
  } else {
    developer.log(
      'Registering NoopNotificationService (degraded mode)',
      name: 'plug_dependency_registrar',
    );
    getIt.registerLazySingleton<INotificationService>(
      NoopNotificationService.new,
    );
  }

  getIt
    ..registerLazySingleton(
      () => SendNotification(getIt<INotificationService>()),
    )
    ..registerLazySingleton(
      () => ScheduleNotification(getIt<INotificationService>()),
    )
    ..registerLazySingleton(
      () => CancelNotification(getIt<INotificationService>()),
    )
    ..registerLazySingleton(
      () => CancelAllNotifications(getIt<INotificationService>()),
    );
}

/// Jitter applied before the first automatic silent update check after boot.
///
/// Spreads the initial probe across the fleet between 30s and 120s, mitigating
/// the thundering herd that would otherwise hit the appcast feed when many
/// clients restart at the same time.
Duration _autoUpdateBootJitter() {
  const minSeconds = 30;
  const rangeSeconds = 90;
  return Duration(seconds: minSeconds + Random.secure().nextInt(rangeSeconds + 1));
}

/// Forces the app to terminate so the silent update helper can replace the
/// running executable. Goes through [WindowManagerService] when available
/// (which already runs [shutdownApp]), then falls back to a hard exit if the
/// process is still alive after [_silentUpdateExitGraceWindow].
///
/// When [INotificationService] is supported, posts a "Plug Agente will close
/// in Ns" toast and waits up to [resolveAutoUpdatePreCloseDelaySeconds] before
/// proceeding. The wait is best-effort and capped, so a desktop running 24/7
/// still resumes the close even if the user did not see the toast.
Future<void> _closeApplicationForSilentUpdate() async {
  await _emitPreCloseNotice();
  if (getIt.isRegistered<WindowManagerService>()) {
    final service = getIt<WindowManagerService>();
    // Flip preventClose/closeToTray off so the close request actually exits
    // the window instead of hiding it to the tray.
    await service.allowQuitForUpdate();
    unawaited(_scheduleSilentUpdateHardExitFallback());
    await service.close();
    return;
  }
  await shutdownApp();
  exit(0);
}

Future<void> _emitPreCloseNotice() async {
  final delaySeconds = resolveAutoUpdatePreCloseDelaySeconds(
    environment: AppEnvironment.snapshot(),
  );
  if (delaySeconds <= 0) return;

  if (getIt.isRegistered<INotificationService>()) {
    final notificationService = getIt<INotificationService>();
    try {
      final result = await notificationService.show(
        title: 'Plug Agente: update ready',
        body: 'Closing in ${delaySeconds}s to install the update.',
      );
      result.fold(
        (_) {},
        (failure) => developer.log(
          'Failed to post pre-close notification (continuing)',
          name: 'plug_dependency_registrar',
          level: 800,
          error: failure,
        ),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Pre-close notification threw (continuing)',
        name: 'plug_dependency_registrar',
        level: 800,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // Wait the configured grace period so the operator sees the notice before
  // the app actually closes. Capped by `_maxPreCloseDelaySeconds` in the
  // config helper to bound this delay.
  await Future<void>.delayed(Duration(seconds: delaySeconds));
}

const Duration _silentUpdateExitGraceWindow = Duration(seconds: 5);

Future<void> _scheduleSilentUpdateHardExitFallback() async {
  await Future<void>.delayed(_silentUpdateExitGraceWindow);
  developer.log(
    'Silent update close did not terminate the process within '
    '${_silentUpdateExitGraceWindow.inSeconds}s; forcing exit(0)',
    name: 'plug_dependency_registrar',
    level: 900,
  );
  exit(0);
}
