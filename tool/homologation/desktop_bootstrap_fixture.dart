import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plug_agente/application/use_cases/ensure_startup_launch_configuration_at_boot.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logging/error_logging_bootstrap.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/error_tracker.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/core/utils/odbc_connection_string_secrets.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/runtime/windows_runtime_probe.dart';
import 'package:plug_agente/infrastructure/services/notification_service.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_runtime.dart';
import 'package:plug_agente/infrastructure/stores/sql_operation_journal_runtime.dart';
import 'package:plug_agente/presentation/boot/app_initializer.dart';
import 'package:plug_agente/presentation/boot/app_root.dart';

import 'action_io_desktop_provision.dart';

// Explicit Windows debug fixture. Real AppInitializer, DI, shell, DPAPI and UI;
// storage lookup and HKCU auto-start repair are isolated from the installed app.
Future<void> main() async {
  final requested = Platform.environment['PLUG_AGENT_BOOTSTRAP_ROOT'];
  final url = Platform.environment['PLUG_AGENT_BOOTSTRAP_URL'];
  final token = Platform.environment['PLUG_AGENT_BOOTSTRAP_TOKEN'];
  final hubAgentId = Platform.environment['PLUG_AGENT_BOOTSTRAP_HUB_AGENT_ID'];
  final hubClientId = Platform.environment['PLUG_AGENT_BOOTSTRAP_HUB_CLIENT_ID'];
  final uuid = RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$');
  if ((hubAgentId == null) != (hubClientId == null) ||
      (hubAgentId != null && (!uuid.hasMatch(hubAgentId) || !uuid.hasMatch(hubClientId!)))) {
    throw StateError('Explicit private hub identities must be paired UUIDs.');
  }
  final agentId = hubAgentId ?? 'agent-bootstrap-test';
  final clientId = hubClientId ?? 'desktop-fixture-client';
  final configured = Platform.environment['PLUG_AGENT_BOOTSTRAP_PROFILE'] == 'configured';
  final actionIoMode = Platform.environment['PLUG_AGENT_BOOTSTRAP_ACTION_IO'];
  if (actionIoMode != null && actionIoMode != 'enabled' && actionIoMode != 'disabled') {
    throw StateError('Explicit bootstrap I/O mode is invalid.');
  }
  final actionIoEnabled = actionIoMode == 'enabled';
  final inspect = Platform.environment['PLUG_AGENT_BOOTSTRAP_INSPECT'] == 'true';
  final notificationId = Platform.environment['PLUG_AGENT_BOOTSTRAP_NOTIFICATION_ID'];
  final notificationGuid = Platform.environment['PLUG_AGENT_BOOTSTRAP_NOTIFICATION_GUID'];
  if (notificationId != null &&
      (!RegExp(r'^PlugDatabase\.Homologacao\.[a-f0-9]{32}$').hasMatch(notificationId) ||
          notificationGuid == null ||
          !RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$').hasMatch(notificationGuid))) {
    throw StateError('Exclusive Windows notification identity is required.');
  }
  if (requested == null || url == null || (!configured && token == null)) {
    throw StateError('Explicit bootstrap fixture required.');
  }
  final root = Directory(requested).resolveSymbolicLinksSync();
  if (Directory(root).parent.path != Directory.systemTemp.resolveSymbolicLinksSync() ||
      !p.basename(root).startsWith('sql-operation-bootstrap-') ||
      Directory.current.resolveSymbolicLinksSync() != root ||
      Uri.parse(url).host != '127.0.0.1') {
    throw StateError('Private bootstrap scope is invalid.');
  }
  PathProviderPlatform.instance = _FixturePaths(root);
  final storage = GlobalStorageContext(appDirectoryPath: p.join(root, 'data'));
  Directory(storage.appDirectoryPath).createSync();
  final actionIoEvidenceExisted = File(storage.actionIoJournalFilePath).existsSync();
  // No update/feed or saved automatic actions exist in the fresh private profile.
  if (!File(storage.settingsFilePath).existsSync()) {
    File(storage.settingsFilePath).writeAsStringSync(
      jsonEncode({
        'settings.automatic_silent_updates_enabled': false,
        'settings.automatic_silent_updates_auto_apply_enabled': false,
        'settings.update_notifications_enabled': false,
        'feature_enable_agent_actions': actionIoEnabled,
        'feature_enable_remote_agent_actions': actionIoEnabled,
        'feature_enable_action_io': actionIoEnabled,
        // The configured fixture deliberately has no reachable business DB.
        'odbc_pool_size': 1,
        'odbc_pool_size_user_configured': true,
        'odbc_login_timeout_seconds': 1,
      }),
      flush: true,
    );
  }
  File(p.join(root, '.env')).writeAsStringSync('APP_ENV=homologation\nENABLE_SQL_OPERATIONS=false\n', flush: true);
  Object? failure;
  StackTrace? failureStack;
  var phase = 'initialize';
  FlutterError.onError = (details) {
    if (failure == null) failureStack = details.stack;
    failure ??= details.exception;
  };
  await runZonedGuarded(
    () async {
      if (inspect) enableFlutterDriverExtension(enableTextEntryEmulation: false);
      WidgetsFlutterBinding.ensureInitialized();
      await ErrorLoggingBootstrap.initializeEarly(candidateLogDirectories: [p.join(root, 'logs')]);
      final initializer = AppInitializer(
        runtimeProbe: WindowsRuntimeProbe(),
        setupDependenciesOverride: ({required capabilities, runtimeDetectionDiagnostics}) async {
          await setupDependencies(
            // These OS registrations share the installed app's identity. The
            // native window/tray and all core persistence/ODBC/RPC remain real.
            capabilities: RuntimeCapabilities(
              mode: capabilities.mode,
              supportsTray: capabilities.supportsTray,
              supportsWindowManager: capabilities.supportsWindowManager,
              supportsNotifications: notificationId != null && capabilities.supportsNotifications,
              supportsAutoUpdate: false,
            ),
            runtimeDetectionDiagnostics: runtimeDetectionDiagnostics,
            storageContext: storage,
          );
          if (notificationId != null) {
            await getIt.unregister<INotificationService>();
            getIt.registerSingleton<INotificationService>(
              NotificationService(
                windowsSettings: WindowsInitializationSettings(
                  appName: 'Plug Agente Homologacao',
                  appUserModelId: notificationId,
                  guid: notificationGuid!,
                ),
              ),
            );
          }
          if (configured) await _prepareConfiguredProfile(root, url);
        },
        // HKCU repair is a machine-level policy and remains a separate installer test.
        ensureStartupLaunchConfigurationOverride: (_) async =>
            const EnsureStartupLaunchConfigurationAtBootOutcome(isAutostartLaunch: false),
      );
      final boot = await initializer.initialize(const []);
      phase = 'persistence';
      if (!boot.capabilities.canRunCore || getIt<FeatureFlags>().enableSqlOperations) {
        throw StateError('Default native bootstrap is not safe or operational.');
      }
      final actionIoRuntime = getIt<ActionIoJournalRuntime>();
      if (getIt<FeatureFlags>().enableActionIo != actionIoEnabled) {
        throw StateError('Persisted I/O mode differs from the explicit fixture mode.');
      }
      final actionIoEvidenceExists = File(storage.actionIoJournalFilePath).existsSync();
      final actionIoExpectedReady = actionIoEnabled || actionIoEvidenceExisted;
      if (actionIoRuntime.isReady != actionIoExpectedReady || actionIoEvidenceExists != actionIoExpectedReady) {
        throw StateError('Bootstrap did not prepare or recover the I/O journal.');
      }
      if (notificationId != null) {
        (await getIt<INotificationService>().show(
          title: 'Plug Agente — homologação',
          body: 'Teste local de integração com o Windows.',
          payload: 'homologation',
        )).getOrThrow();
        (await getIt<INotificationService>().cancelAll()).getOrThrow();
      }
      final configs = (await getIt<IAgentConfigRepository>().getAllMetadata()).getOrThrow();
      if (configs.length != (configured ? 1 : 0)) throw StateError('Private profile count differs from fixture mode.');
      final persistedToken = configured
          ? (await getIt<IAgentConfigRepository>().getCurrentConfig()).getOrThrow().authToken
          : null;
      // Verify the registered production secret adapter and native backend.
      final secrets = getIt<ITokenSecretStore>();
      await secrets.saveSecret('bootstrap-probe', 'private-roundtrip');
      if (await secrets.readSecret('bootstrap-probe') != 'private-roundtrip') {
        throw StateError('DPAPI roundtrip failed.');
      }
      await secrets.deleteSecret('bootstrap-probe');
      getIt<SqlOperationJournalRuntime>().journal;
      final integrity = await getIt<AppDatabase>().customSelect('PRAGMA quick_check').get();
      if (integrity.single.data.values.single != 'ok') throw StateError('Bootstrap database integrity failed.');
      runApp(
        AppRoot(
          initialRoute: boot.initialRoute,
          capabilities: boot.capabilities,
          runDeferredBootstrap: boot.runDeferredBootstrap,
        ),
      );
      phase = 'first-frame';
      await WidgetsBinding.instance.endOfFrame;
      if (inspect) {
        final window = getIt<IDesktopWindowService>();
        await window.show();
        if (!await window.isVisible()) {
          throw StateError('Private desktop inspection requires a visible native window.');
        }
        final service = await developer.Service.getInfo();
        if (service.serverUri == null) throw StateError('Debug VM service is unavailable.');
        await File(p.join(root, 'debug-service.json')).writeAsString(jsonEncode({'uri': service.serverUri.toString()}));
      }
      phase = 'socket-connect';
      if (Platform.environment['PLUG_AGENT_BOOTSTRAP_ACTION_IO_EXECUTE'] == 'true') {
        if (!actionIoEnabled || configured) {
          throw StateError('Private I/O execution requires an enabled fresh profile.');
        }
        await provisionDesktopActionIo(
          root,
          agentId: agentId,
          clientId: clientId,
          secondClientId: Platform.environment['PLUG_AGENT_BOOTSTRAP_SECOND_CLIENT_ID'],
          thirdClientId: Platform.environment['PLUG_AGENT_BOOTSTRAP_THIRD_CLIENT_ID'],
        );
      }
      final transport = getIt<ITransportClient>();
      if (configured) {
        // A configured but unreachable SQL Server may consume its native
        // connection timeout during pool warm-up before Hub auto-connect.
        final deadline = DateTime.now().add(const Duration(seconds: 65));
        // AppRoot must restore and refresh the session itself; no direct connect
        // or credentials fallback is allowed in the configured-profile mode.
        while (!transport.isConnected) {
          if (failure != null || DateTime.now().isAfter(deadline)) {
            throw StateError('Configured startup did not restore the Hub session.');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        final restored = (await getIt<IAgentConfigRepository>().getCurrentConfig()).getOrThrow();
        if (restored.authToken == null ||
            restored.authToken == persistedToken ||
            restored.password != _fixturePassword) {
          throw StateError('Configured startup did not refresh the protected session or restore ODBC credentials.');
        }
      } else {
        (await transport.connect(url, agentId, authToken: token)).getOrThrow();
      }
      final readyFile = File(p.join(root, 'boot-ready.json.tmp'));
      await readyFile.writeAsString(
        jsonEncode({
          'core': true,
          'firstFrame': true,
          'sqlOperationsDefault': false,
          'actionIoEnabled': actionIoEnabled,
          'actionIoJournalReady': actionIoRuntime.isReady,
          'configCount': configs.length,
          'configuredAutoSession': configured,
          'notifications': notificationId != null,
          'configId': configured ? configs.single.id : null,
          'secretRoundtrip': true,
          'databaseIntegrity': 'ok',
          'runtime': boot.capabilities.mode.name,
          'instanceId': getIt<AgentRuntimeIdentity>().runtimeInstanceId,
          'sessionId': getIt<AgentRuntimeIdentity>().runtimeSessionId,
        }),
        flush: true,
      );
      await readyFile.rename(p.join(root, 'boot-ready.json'));
      final deadline = DateTime.now().add(inspect ? const Duration(minutes: 5) : const Duration(seconds: 35));
      phase = 'serve';
      while (!File(p.join(root, 'stop')).existsSync()) {
        if (failure != null) throw StateError('Native UI reported an uncaught error.');
        if (DateTime.now().isAfter(deadline)) throw StateError('Bootstrap fixture controller timed out.');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      phase = 'shutdown';
      // Dispose UI subscriptions while their providers and transport still exist.
      runApp(const SizedBox.shrink());
      await WidgetsBinding.instance.endOfFrame;
      await shutdownApp();
      if (actionIoRuntime.isReady) {
        throw StateError('Application shutdown did not close the I/O journal.');
      }
      await getIt.reset();
      await ErrorLoggingBootstrap.dispose();
      if (failure != null) throw StateError('Native bootstrap or shutdown reported an uncaught error.');
      await File(p.join(root, 'boot-closed')).writeAsString('verified', flush: true);
      exit(0);
    },
    (error, stack) {
      failure ??= error;
      ErrorTracker.captureException(error, stack, operation: 'homologation_bootstrap');
      File(
        p.join(root, 'boot-failed.json'),
      ).writeAsStringSync(jsonEncode({
        'phase': phase,
        'type': failure.runtimeType.toString(),
        'frames': (failureStack ?? stack).toString().split('\n').take(6).toList(),
      }), flush: true);
      exit(1);
    },
  );
  exit(1);
}

const _fixturePassword = 'private-bootstrap-odbc-only';

Future<void> _prepareConfiguredProfile(String root, String url) async {
  final repository = getIt<IAgentConfigRepository>();
  final configs = (await repository.getAllMetadata()).getOrThrow();
  final bootstrap = File(p.join(root, 'profile-bootstrap.json'));
  if (configs.isEmpty) {
    if (!bootstrap.existsSync()) throw StateError('Initial configured profile requires an explicit private seed.');
    final seed = jsonDecode(await bootstrap.readAsString()) as Map<String, dynamic>;
    if (seed['serverUrl'] != url || seed['agentId'] is! String) throw StateError('Private Hub seed mismatch.');
    (await repository.save(
      Config(
        id: 'f5af5822-1948-4197-89ea-56cc57a236c0',
        serverUrl: url,
        agentId: seed['agentId'] as String,
        authToken: seed['accessToken'] as String,
        refreshToken: seed['refreshToken'] as String,
        driverName: 'SQL Server',
        odbcDriverName: 'ODBC Driver 17 for SQL Server',
        connectionString:
            'DRIVER={ODBC Driver 17 for SQL Server};SERVER=127.0.0.1,1;DATABASE=bootstrap_test;UID=fixture;PWD=$_fixturePassword',
        username: 'fixture',
        password: _fixturePassword,
        databaseName: 'bootstrap_test',
        host: '127.0.0.1',
        port: 1,
        nome: 'Private bootstrap fixture',
        nomeFantasia: 'Private bootstrap fixture',
        cnaeCnpjCpf: '52998224725',
        celular: '11988887777',
        email: 'fixture@example.com',
        endereco: 'Fixture',
        numeroEndereco: '1',
        bairro: 'Fixture',
        cep: '01001000',
        nomeMunicipio: 'Fixture',
        ufMunicipio: 'SP',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    )).getOrThrow();
  } else if (bootstrap.existsSync() || configs.length != 1 || configs.single.serverUrl != url) {
    throw StateError('Restart must restore exactly one private profile without bootstrap credentials.');
  }
  final row = await getIt<AppDatabase>().select(getIt<AppDatabase>().configTable).getSingle();
  if (row.authToken != null ||
      row.refreshToken != null ||
      row.authPassword != null ||
      OdbcConnectionStringSecrets.extractPasswordFromConnectionString(row.connectionString) != null) {
    throw StateError('Configured profile stored plaintext secrets in SQLite.');
  }
}

class _FixturePaths extends PathProviderPlatform {
  _FixturePaths(this.root);
  final String root;
  String directory(String name) => (Directory(p.join(root, name))..createSync()).path;
  @override
  Future<String?> getApplicationSupportPath() async => directory('support');
  @override
  Future<String?> getApplicationDocumentsPath() async => directory('documents');
  @override
  Future<String?> getTemporaryPath() async => directory('temp');
}
