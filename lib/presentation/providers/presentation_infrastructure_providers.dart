import 'package:plug_agente/application/services/agent_register_profile_provider.dart';
import 'package:plug_agente/application/use_cases/fetch_agent_hub_profile.dart';
import 'package:plug_agente/application/use_cases/lookup_agent_cep.dart';
import 'package:plug_agente/application/use_cases/lookup_agent_cnpj.dart';
import 'package:plug_agente/application/use_cases/reload_odbc_runtime_dependencies.dart';
import 'package:plug_agente/application/use_cases/sync_agent_profile_with_hub.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/hub_resilience_config.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_local_app_data_backup_service.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// Composition-root wiring for presentation-layer services resolved from getIt.
List<SingleChildWidget> buildPresentationInfrastructureProviders({
  required RuntimeCapabilities capabilities,
}) {
  return <SingleChildWidget>[
    Provider<RuntimeCapabilities>.value(value: capabilities),
    if (getIt.isRegistered<IAppSettingsStore>()) Provider<IAppSettingsStore>(create: (_) => getIt<IAppSettingsStore>()),
    if (getIt.isRegistered<RuntimeDetectionDiagnostics>())
      Provider<RuntimeDetectionDiagnostics>(create: (_) => getIt<RuntimeDetectionDiagnostics>()),
    if (getIt.isRegistered<IMetricsCollector>()) Provider<IMetricsCollector>(create: (_) => getIt<IMetricsCollector>()),
    if (getIt.isRegistered<FeatureFlags>()) Provider<FeatureFlags>(create: (_) => getIt<FeatureFlags>()),
    if (getIt.isRegistered<HubResilienceConfig>())
      Provider<HubResilienceConfig>(create: (_) => getIt<HubResilienceConfig>()),
    if (getIt.isRegistered<PayloadSigningConfig>())
      Provider<PayloadSigningConfig>(create: (_) => getIt<PayloadSigningConfig>()),
    if (getIt.isRegistered<ILocalAppDataBackupService>())
      Provider<ILocalAppDataBackupService>(create: (_) => getIt<ILocalAppDataBackupService>()),
    if (getIt.isRegistered<IOdbcConnectionSettings>())
      Provider<IOdbcConnectionSettings>(create: (_) => getIt<IOdbcConnectionSettings>()),
    if (getIt.isRegistered<IConnectionPool>()) Provider<IConnectionPool>(create: (_) => getIt<IConnectionPool>()),
    if (getIt.isRegistered<IAuthorizationMetricsCollector>())
      Provider<IAuthorizationMetricsCollector>(create: (_) => getIt<IAuthorizationMetricsCollector>()),
    if (getIt.isRegistered<IDeprecationMetricsCollector>())
      Provider<IDeprecationMetricsCollector>(create: (_) => getIt<IDeprecationMetricsCollector>()),
    if (getIt.isRegistered<IStartupService>()) Provider<IStartupService>(create: (_) => getIt<IStartupService>()),
    if (getIt.isRegistered<IWindowManagerService>())
      Provider<IWindowManagerService>(create: (_) => getIt<IWindowManagerService>()),
    if (getIt.isRegistered<LookupAgentCnpj>()) Provider<LookupAgentCnpj>(create: (_) => getIt<LookupAgentCnpj>()),
    if (getIt.isRegistered<LookupAgentCep>()) Provider<LookupAgentCep>(create: (_) => getIt<LookupAgentCep>()),
    if (getIt.isRegistered<SyncAgentProfileWithHub>())
      Provider<SyncAgentProfileWithHub>(create: (_) => getIt<SyncAgentProfileWithHub>()),
    if (getIt.isRegistered<FetchAgentHubProfile>())
      Provider<FetchAgentHubProfile>(create: (_) => getIt<FetchAgentHubProfile>()),
    if (getIt.isRegistered<ReloadOdbcRuntimeDependencies>())
      Provider<ReloadOdbcRuntimeDependencies>(create: (_) => getIt<ReloadOdbcRuntimeDependencies>()),
    if (getIt.isRegistered<AgentRegisterProfileProvider>())
      Provider<AgentRegisterProfileProvider>(create: (_) => getIt<AgentRegisterProfileProvider>()),
  ];
}
