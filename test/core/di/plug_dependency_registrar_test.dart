import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/actions/action_io_admission.dart';
import 'package:plug_agente/application/actions/action_io_authorization.dart';
import 'package:plug_agente/application/actions/action_io_local_intent_validator.dart';
import 'package:plug_agente/application/actions/agent_action_live_processes.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/save_agent_config.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/hub_resilience_config.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/core/di/plug_dependency_registrar.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/core/settings/agent_action_cpu_settings.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart' show GlobalAppSettingsStore, IAppSettingsStore;
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_history.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_output.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_authorization_trust_invalidator.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_lifecycle.dart';
import 'package:plug_agente/infrastructure/actions/script_action_process_runner.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/settings/odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_runtime.dart';

/// Avoids `odbc_fast` loading `libodbc_engine` (missing on Linux CI).
class _MockOdbcService extends Mock implements odbc.OdbcService {}

class _FakeOdbcWorkerLocator implements odbc.ServiceLocator {
  _FakeOdbcWorkerLocator() : asyncService = _MockOdbcService();

  @override
  final odbc.OdbcService asyncService;

  @override
  odbc.ConnectionOptions get recommendedConnectionOptions => const odbc.ConnectionOptions();

  @override
  odbc.PoolOptions get recommendedPoolOptions => const odbc.PoolOptions();

  @override
  bool get isAsyncMode => true;

  @override
  void shutdown() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late GetIt sl;
  late odbc.ServiceLocator odbcLocator;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plug_registrar_test_');
    sl = GetIt.asNewInstance();
    odbcLocator = _FakeOdbcWorkerLocator();

    final storage = GlobalStorageContext(appDirectoryPath: tempDir.path);
    final settings = GlobalAppSettingsStore(filePath: '${tempDir.path}/settings.json');
    await settings.initialize();

    sl
      ..registerSingleton<GlobalStorageContext>(storage)
      ..registerSingleton<IAppSettingsStore>(settings)
      ..registerSingleton<FeatureFlags>(FeatureFlags(settings))
      ..registerSingleton<HubResilienceConfig>(HubResilienceConfig(sl<FeatureFlags>()))
      ..registerSingleton<PayloadSigningConfig>(
        PayloadSigningConfig.empty(
          secureStorageAvailable: false,
        ),
      )
      ..registerSingleton<AgentRuntimeIdentity>(
        await AgentRuntimeIdentity.load(settings: settings),
      );

    final odbcSettings = OdbcConnectionSettings(settings);
    await odbcSettings.load();
    sl
      ..registerSingleton<IOdbcConnectionSettings>(odbcSettings)
      ..registerSingleton<OdbcRuntimeTuning>(
        OdbcRuntimeTuning.forPoolSize(
          poolSize: odbcSettings.poolSize,
          processorCount: 4,
        ),
      );

    registerPlugDependencyGraph(sl, odbcWorkerLocator: odbcLocator);
  });

  tearDown(() async {
    if (sl.isRegistered<AppDatabase>()) {
      await sl<AppDatabase>().close();
    }
    await sl.reset();
    odbcLocator.shutdown();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('action diagnostics and CPU policy resolve without a dependency cycle', () {
    expect(sl<AgentActionCpuSettings>().limitPercent, 0);
    expect(sl<AgentActionLiveProcesses>().forAction('unused'), isEmpty);
    expect(sl<AgentActionProcessLifecycle>(), same(sl<AgentActionProcessLifecycle>()));
    expect(sl<ScriptActionProcessRunner>(), isA<ScriptActionProcessRunner>());
  });

  test('registers persistence before transport hub dependencies resolve', () {
    expect(sl.isRegistered<ActionIoAdmission>(), isTrue);
    expect(sl<ActionIoAuthorization>(), isA<ActionIoAuthorization>());
    expect(sl<ActionIoLocalIntentValidator>(), isA<ActionIoLocalIntentValidator>());
    expect(sl.isRegistered<ActionIoJournalRuntime>(), isTrue);
    final io = sl<ActionIoJournalRuntime>();
    expect(sl<IActionIoLocalHistory>(), same(io));
    expect(sl<IActionIoLocalOutput>(), same(io));
    expect(io.path, sl<GlobalStorageContext>().actionIoJournalFilePath);
    expect(io.isReady, isFalse);
    expect(File(io.path).existsSync(), isFalse);
    expect(sl.isRegistered<AppDatabase>(), isTrue);
    expect(sl.isRegistered<IAgentConfigRepository>(), isTrue);
    expect(sl.isRegistered<ITransportClient>(), isTrue);
    expect(sl<ConnectToHub>(), isA<ConnectToHub>());
  });

  test('configuration services resolve their shared authorization invalidator without cycles', () {
    expect(sl<IAuthorizationTrustInvalidator>(), same(sl<IAuthorizationTrustInvalidator>()));
    expect(sl<ActiveConfigResolver>(), isA<ActiveConfigResolver>());
    expect(sl<SaveAgentConfig>(), isA<SaveAgentConfig>());
  });

  test('registers critical application singletons after full graph registration', () {
    expect(sl.isRegistered<SaveAgentConfig>(), isTrue);
    expect(sl.isRegistered<HubSessionCoordinator>(), isTrue);
    expect(sl.isRegistered<ConnectToHub>(), isTrue);
  });
}
