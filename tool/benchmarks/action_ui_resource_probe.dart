import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plug_agente/application/actions/agent_action_live_processes.dart';
import 'package:plug_agente/application/use_cases/ensure_startup_launch_configuration_at_boot.dart';
import 'package:plug_agente/core/constants/app_version.g.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logging/error_logging_bootstrap.dart';
import 'package:plug_agente/core/routes/app_routes.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/infrastructure/runtime/windows_runtime_probe.dart';
import 'package:plug_agente/presentation/boot/app_initializer.dart';
import 'package:plug_agente/presentation/boot/app_root.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_actions_page.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:provider/provider.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

// Explicit diagnostic entrypoint: real bootstrap, providers, window, tray and
// executor; fresh private storage, no Hub, credentials or business actions.
Future<void> main() async {
  final requested = Platform.environment['PLUG_UI_PROBE_ROOT'];
  if (!Platform.isWindows || requested == null) throw StateError('Explicit Windows probe root required.');
  final root = Directory(requested).resolveSymbolicLinksSync();
  if (Directory(root).parent.path != Directory.systemTemp.resolveSymbolicLinksSync() ||
      !p.basename(root).startsWith('plug-ui-probe-') ||
      Directory(root).listSync().isNotEmpty) {
    throw StateError('Probe requires an empty direct temporary directory.');
  }
  final seconds = int.parse(Platform.environment['PLUG_UI_PROBE_SECONDS'] ?? '90');
  if (seconds < 30 || seconds > 900) throw StateError('Phase duration must be 30..900 seconds.');
  Directory.current = root;
  PathProviderPlatform.instance = _ProbePaths(root);
  final storage = GlobalStorageContext(appDirectoryPath: p.join(root, 'data'));
  Directory(storage.appDirectoryPath).createSync();
  File(storage.settingsFilePath).writeAsStringSync(
    jsonEncode({
      'settings.automatic_silent_updates_enabled': false,
      'settings.automatic_silent_updates_auto_apply_enabled': false,
      'settings.update_notifications_enabled': false,
      'feature_enable_agent_actions': true,
      'feature_enable_remote_agent_actions': false,
    }),
  );
  File('.env').writeAsStringSync('APP_ENV=homologation\nENABLE_SQL_OPERATIONS=false\n');
  final evidence = File(p.join(root, 'samples.jsonl'));
  void record(Map<String, Object?> value) =>
      evidence.writeAsStringSync('${jsonEncode(value)}\n', mode: FileMode.append);
  record({
    'metadata': {
      'format': 1,
      'appVersion': appVersion,
      'sourceRevision': Platform.environment['PLUG_UI_PROBE_REVISION'] ?? 'unknown',
      'sourceDirty': Platform.environment['PLUG_UI_PROBE_DIRTY'] ?? 'unknown',
      'machineId': Platform.environment['PLUG_UI_PROBE_MACHINE'] ?? 'unknown',
      'sdkRevision': Platform.environment['PLUG_UI_PROBE_SDK'] ?? 'unknown',
      'os': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'mode': const bool.fromEnvironment('dart.vm.product')
          ? 'release'
          : const bool.fromEnvironment('dart.vm.profile')
          ? 'profile'
          : 'debug',
      'phaseSeconds': seconds,
      'scenario': 'silent-wait-v1',
      'startedAt': DateTime.now().toUtc().toIso8601String(),
    },
  });
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        record({'error': details.exceptionAsString(), 'stack': details.stack.toString()});
        FlutterError.presentError(details);
      };
      await ErrorLoggingBootstrap.initializeEarly(candidateLogDirectories: [p.join(root, 'logs')]);
      final boot = await AppInitializer(
        runtimeProbe: WindowsRuntimeProbe(),
        setupDependenciesOverride: ({required capabilities, runtimeDetectionDiagnostics}) => setupDependencies(
          capabilities: RuntimeCapabilities(
            mode: capabilities.mode,
            supportsTray: capabilities.supportsTray,
            supportsWindowManager: capabilities.supportsWindowManager,
            supportsNotifications: false,
            supportsAutoUpdate: false,
          ),
          runtimeDetectionDiagnostics: runtimeDetectionDiagnostics,
          storageContext: storage,
        ),
        ensureStartupLaunchConfigurationOverride: (_) async =>
            const EnsureStartupLaunchConfigurationAtBootOutcome(isAutostartLaunch: false),
        resolveInitialRouteOverride: (_) => AppRoutes.agentActions,
      ).initialize(const []);
      final definition = AgentActionDefinition(
        id: '0c6c87c1-0342-4448-a60b-980d10750d60',
        name: 'Diagnóstico: espera longa sem saída',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'ping -n ${seconds * 4 + 121} 127.0.0.1 >nul'),
        policies: AgentActionDefinitionPolicies(
          timeout: AgentActionTimeoutPolicy(maxRuntime: Duration(seconds: seconds * 4 + 180)),
        ),
      );
      (await getIt<IAgentActionRepository>().saveDefinition(definition)).getOrThrow();
      final tickers = ValueNotifier(true);
      runApp(
        ValueListenableBuilder<bool>(
          valueListenable: tickers,
          builder: (context, enabled, child) => TickerMode(enabled: enabled, child: child!),
          child: AppRoot(
            initialRoute: AppRoutes.agentActions,
            capabilities: boot.capabilities,
            runDeferredBootstrap: boot.runDeferredBootstrap,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 10));
      final service = await developer.Service.getInfo();
      File(
        p.join(root, 'service.json'),
      ).writeAsStringSync(jsonEncode({'uri': service.serverUri?.toString(), 'pid': pid}));
      AgentActionsProvider? provider;
      void visit(Element element) {
        if (element.widget is AgentActionsPage) provider = element.read<AgentActionsProvider>();
        element.visitChildren(visit);
      }

      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      final actions = provider;
      if (actions == null) throw StateError('Real actions page is not mounted.');
      if (!getIt<ITrayService>().isReady) throw StateError('Native tray unavailable.');
      await actions.load();
      actions.selectAction(definition.id);
      var notifications = 0;
      void changed() => notifications++;
      actions.addListener(changed);
      var frames = 0;
      var buildMicros = 0;
      var rasterMicros = 0;
      void timings(List<FrameTiming> batch) {
        for (final frame in batch) {
          frames++;
          buildMicros += frame.buildDuration.inMicroseconds;
          rasterMicros += frame.rasterDuration.inMicroseconds;
        }
      }

      WidgetsBinding.instance.addTimingsCallback(timings);
      final watch = Stopwatch()..start();
      var phase = 'idle-visible';
      void sample() => record({
        'phase': phase,
        'elapsedMs': watch.elapsedMilliseconds,
        'pid': pid,
        'processors': Platform.numberOfProcessors,
        ..._nativeResources(),
        'frames': frames,
        'buildMicros': buildMicros,
        'rasterMicros': rasterMicros,
        'providerNotifications': notifications,
        'running': actions.summaryRunningCount,
        'actionJobs': [
          for (final process in getIt<AgentActionLiveProcesses>().forAction(definition.id))
            {'pid': process.pid, 'cpuMicros': process.readCpu().getOrThrow().inMicroseconds},
        ],
        'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
        'renderingEnabled': (getIt<IDesktopWindowService>() as IWindowRenderActivity).renderingEnabled.value,
      });
      final timer = Timer.periodic(const Duration(seconds: 5), (_) => sample());
      Future<void>? running;
      try {
        sample();
        await Future<void>.delayed(const Duration(seconds: 30));
        phase = 'running-visible';
        running = actions.runSelectedAction();
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!actions.isDefinitionRunning(definition.id)) {
          throw StateError('Action did not start: ${actions.errorMessage}');
        }
        sample();
        await Future<void>.delayed(Duration(seconds: seconds));
        (await getIt<IDesktopWindowService>().setCloseToTray(value: true)).getOrThrow();
        await windowManager.close();
        await Future<void>.delayed(const Duration(seconds: 2));
        if (await windowManager.isVisible()) throw StateError('Close-to-tray did not hide the native window.');
        phase = 'running-tray';
        sample();
        await Future<void>.delayed(Duration(seconds: seconds));
        await getIt<IDesktopWindowService>().show();
        phase = 'running-restored';
        sample();
        await Future<void>.delayed(Duration(seconds: seconds));
        phase = 'running-visible-tickers-off';
        tickers.value = false;
        sample();
        await Future<void>.delayed(Duration(seconds: seconds));
        tickers.value = true;
        await actions.stopRunningDefinition(definition);
        await running;
        phase = 'finished-visible';
        await Future<void>.delayed(const Duration(seconds: 30));
        sample();
      } finally {
        timer.cancel();
        actions.removeListener(changed);
        WidgetsBinding.instance.removeTimingsCallback(timings);
        if (actions.isDefinitionRunning(definition.id)) await actions.stopRunningDefinition(definition);
        if (running != null) await running;
        await getIt<ITrayService>().dispose();
        await getIt.reset();
      }
      record({'completed': true});
      exit(0);
    },
    (error, stack) {
      record({'fatal': '$error', 'stack': '$stack'});
      exit(1);
    },
  );
}

Map<String, Object?> _nativeResources() => using((arena) {
  final memory = arena<PROCESS_MEMORY_COUNTERS>();
  memory.ref.cb = sizeOf<PROCESS_MEMORY_COUNTERS>();
  final memoryResult = GetProcessMemoryInfo(GetCurrentProcess(), memory, memory.ref.cb);
  final creation = arena<FILETIME>();
  final ended = arena<FILETIME>();
  final kernel = arena<FILETIME>();
  final user = arena<FILETIME>();
  final cpu = GetProcessTimes(GetCurrentProcess(), creation, ended, kernel, user);
  if (!memoryResult.value || !cpu.value) throw StateError('Native resource measurement failed.');
  int ticks(FILETIME value) => (value.dwHighDateTime << 32) | value.dwLowDateTime;
  return {
    'rssBytes': memory.ref.WorkingSetSize,
    'commitBytes': memory.ref.PagefileUsage,
    'cpuMicros': (ticks(kernel.ref) + ticks(user.ref)) ~/ 10,
  };
});

class _ProbePaths extends PathProviderPlatform {
  _ProbePaths(this.root);
  final String root;
  String directory(String name) => (Directory(p.join(root, name))..createSync()).path;
  @override
  Future<String?> getApplicationSupportPath() async => directory('support');
  @override
  Future<String?> getApplicationDocumentsPath() async => directory('documents');
  @override
  Future<String?> getTemporaryPath() async => directory('temp');
}
