import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:get_it/get_it.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/actions/action_environment_resolver.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_backup_sanitizer.dart';
import 'package:plug_agente/application/actions/agent_action_dangerous_command_policy_enforcer.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/application/actions/agent_action_execution_gate_chain.dart';
import 'package:plug_agente/application/actions/agent_action_prepared_execution_cache.dart';
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
import 'package:plug_agente/application/gateway/queued_streaming_database_gateway.dart';
import 'package:plug_agente/application/observability/i_auto_update_diagnostics_gateway.dart';
import 'package:plug_agente/application/observability/update_check_id_recorder.dart';
import 'package:plug_agente/application/ports/i_agent_actions_bundle_file_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/application/repositories/app_preferences_repository.dart';
import 'package:plug_agente/application/repositories/i_app_preferences_repository.dart';
import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/application/repositories/update_preferences_repository.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/factories/agent_action_rpc_method_handler_operations_factory.dart';
import 'package:plug_agente/application/rpc/factories/agent_metadata_rpc_method_handler_operations_factory.dart';
import 'package:plug_agente/application/rpc/factories/default_rpc_method_handler_operations_factory.dart';
import 'package:plug_agente/application/rpc/factories/sql_rpc_method_handler_operations_factory.dart';
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
import 'package:plug_agente/application/services/hub_access_token_refresh_gate.dart';
import 'package:plug_agente/application/services/hub_access_token_renewer.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/services/rpc_idempotency_cache_periodic_purge.dart';
import 'package:plug_agente/application/services/settings_backed_pending_silent_update_store.dart';
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
import 'package:plug_agente/application/use_cases/fetch_agent_hub_profile.dart';
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
import 'package:plug_agente/application/use_cases/set_start_with_windows.dart';
import 'package:plug_agente/application/use_cases/set_tray_behavior_preference.dart';
import 'package:plug_agente/application/use_cases/slice_agent_action_captured_output.dart';
import 'package:plug_agente/application/use_cases/sync_agent_profile_with_hub.dart';
import 'package:plug_agente/application/use_cases/sync_startup_status.dart';
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
import 'package:plug_agente/core/runtime/i_uac_detector.dart';
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_app_infrastructure_shutdown_port.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
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
import 'package:plug_agente/domain/repositories/i_auto_update_metrics_collector.dart';
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
import 'package:plug_agente/domain/repositories/i_global_storage_health_snapshot_builder.dart';
import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_hub_availability_probe.dart';
import 'package:plug_agente/domain/repositories/i_hub_session_store.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_local_app_data_backup_service.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_store.dart';
import 'package:plug_agente/domain/repositories/i_odbc_driver_checker.dart';
import 'package:plug_agente/domain/repositories/i_pool_discard_inflight_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_protocol_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_protocol_negotiator.dart';
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/domain/repositories/i_revoked_token_store.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/repositories/sql_execution_queue_metrics_collector.dart';
import 'package:plug_agente/domain/streaming/i_streaming_named_parameter_preparer.dart';
import 'package:plug_agente/infrastructure/actions/action_command_safety_validator.dart';
import 'package:plug_agente/infrastructure/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/agent_actions_bundle_file_gateway.dart';
import 'package:plug_agente/infrastructure/actions/scheduler_lock_failure_resolver.dart';
import 'package:plug_agente/infrastructure/actions/scheduler_lock_metadata_reader.dart';
import 'package:plug_agente/infrastructure/actions/scheduler_stale_lock_recovery.dart';
import 'package:plug_agente/infrastructure/actions/windows_process_lifetime_checker.dart';
import 'package:plug_agente/infrastructure/backup/local_app_data_backup_service.dart';
import 'package:plug_agente/infrastructure/bootstrap/infrastructure_shutdown_port.dart';
import 'package:plug_agente/infrastructure/cache/client_token_policy_memory_cache.dart';
import 'package:plug_agente/infrastructure/config/odbc_recommended_options_merger.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/agent_hub_profile_rest_client.dart';
import 'package:plug_agente/infrastructure/external_services/auth_client.dart';
import 'package:plug_agente/infrastructure/external_services/connected_agents_rest_client.dart';
import 'package:plug_agente/infrastructure/external_services/dio_factory.dart';
import 'package:plug_agente/infrastructure/external_services/hub_availability_probe.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batched_streaming_query_source.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_database_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_driver_checker.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_named_parameter_preparer.dart';
import 'package:plug_agente/infrastructure/external_services/open_cnpj_client.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_client_v2.dart';
import 'package:plug_agente/infrastructure/external_services/throttled_auto_update_diagnostics_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/transport/open_rpc_document_loader.dart';
import 'package:plug_agente/infrastructure/external_services/via_cep_client.dart';
import 'package:plug_agente/infrastructure/health/global_storage_health_snapshot_builder.dart';
import 'package:plug_agente/infrastructure/metrics/authorization_cache_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/authorization_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/deprecation_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_event_bridge.dart';
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
import 'package:plug_agente/infrastructure/repositories/startup_preferences_repository.dart';
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:plug_agente/infrastructure/runtime/windows_uac_detector.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/services/auto_start_service.dart';
import 'package:plug_agente/infrastructure/services/dio_silent_update_installer.dart';
import 'package:plug_agente/infrastructure/services/file_silent_update_launcher_status_reader.dart';
import 'package:plug_agente/infrastructure/services/noop_notification_service.dart';
import 'package:plug_agente/infrastructure/services/notification_service.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_acl_bootstrap.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_acl_marker_store.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_directory_acl_normalizer.dart';
import 'package:plug_agente/infrastructure/storage/icacls_command_runner.dart';
import 'package:plug_agente/infrastructure/stores/agent_action_remote_audit_drift_store.dart';
import 'package:plug_agente/infrastructure/stores/drift_idempotency_store.dart';
import 'package:plug_agente/infrastructure/stores/file_token_audit_store.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_agent_action_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_hub_auth_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_odbc_credential_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_token_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/hub_session_store.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_authorization_decision_cache.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_revoked_token_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_agent_action_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_hub_auth_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_odbc_credential_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_token_audit_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_token_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/odbc_credential_store.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/l10n/agent_action_notification_messages_factory.dart';
import 'package:uuid/uuid.dart';

part 'plug_dependency_registrar_actions_infra.dart';
part 'plug_dependency_registrar_actions_use_cases.dart';
part 'plug_dependency_registrar_application.dart';
part 'plug_dependency_registrar_auth_tokens.dart';
part 'plug_dependency_registrar_auto_update.dart';
part 'plug_dependency_registrar_capability.dart';
part 'plug_dependency_registrar_foundation.dart';
part 'plug_dependency_registrar_health.dart';
part 'plug_dependency_registrar_odbc.dart';
part 'plug_dependency_registrar_persistence.dart';
part 'plug_dependency_registrar_playground.dart';
part 'plug_dependency_registrar_rpc.dart';
part 'plug_dependency_registrar_shutdown.dart';
part 'plug_dependency_registrar_transport_hub.dart';

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

  _registerFoundation(getIt);
  _registerPersistence(getIt);
  _registerActionsInfrastructure(getIt);
  _registerOdbc(getIt, odbcWorkerLocator: odbcWorkerLocator);
  _registerHealth(getIt);
  _registerRpc(
    getIt,
    readPositiveIntEnv: readPositiveIntEnv,
    readNonNegativeIntEnv: readNonNegativeIntEnv,
  );
  _registerTransportHub(getIt);
  _registerApplicationServices(getIt);
  _registerPlayground(getIt);
  _registerActionsUseCases(getIt);
  _registerAutoUpdate(getIt);
  _registerAuthTokens(getIt);
  _registerShutdown(getIt);
}

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
/// Invoked only from `IAutoUpdateOrchestrator.applyPendingSilentUpdate` ÔÇö
/// never from the silent download path, which leaves the agent online.
/// When [INotificationService] is supported, posts a localized "closing in
/// Ns" toast and waits up to [resolveAutoUpdatePreCloseDelaySeconds] before
/// proceeding. [noticeTitle] / [noticeBody] are passed in by the caller
/// (the UI) so the toast text honors the active locale; defaults are kept
/// for callers without a localization context (e.g. shutdown handler).
Future<void> _closeApplicationForSilentUpdate({
  String? noticeTitle,
  String? noticeBody,
}) async {
  await _emitPreCloseNotice(title: noticeTitle, body: noticeBody);
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

Future<void> _emitPreCloseNotice({String? title, String? body}) async {
  final delaySeconds = resolveAutoUpdatePreCloseDelaySeconds(
    environment: AppEnvironment.snapshot(),
  );
  if (delaySeconds <= 0) return;

  if (getIt.isRegistered<INotificationService>()) {
    final notificationService = getIt<INotificationService>();
    try {
      final result = await notificationService.show(
        title: title ?? 'Plug Agente: update ready',
        body: body ?? 'Closing in ${delaySeconds}s to install the update.',
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

IPoolDiscardInflightDiagnostics? _resolvePoolDiscardInflightDiagnostics(
  IDatabaseGateway gateway,
) {
  final inner = gateway is QueuedDatabaseGateway ? gateway.delegate : gateway;
  if (inner is IPoolDiscardInflightDiagnostics) {
    return inner as IPoolDiscardInflightDiagnostics;
  }
  return null;
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
