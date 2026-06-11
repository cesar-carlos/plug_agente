import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/bootstrap/agent_actions_boot_phases.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/i_windows_runtime_probe.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/runtime/runtime_mode.dart';
import 'package:plug_agente/core/runtime/windows_version_info.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/presentation/boot/app_initializer.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('passes detected runtime diagnostics through bootstrap setup callback', () async {
    var capturedCapabilities = null as RuntimeCapabilities?;
    var capturedDiagnostics = null as RuntimeDetectionDiagnostics?;
    var bootstrapPhasesRan = false;
    var desktopFeaturesInitialized = false;

    final initializer = AppInitializer(
      runtimeProbe: _FakeWindowsRuntimeProbe(
        result: const Success(
          WindowsVersionInfo(
            majorVersion: 10,
            minorVersion: 0,
            buildNumber: 26200,
            isServer: false,
            productName: 'Windows 11 Pro',
          ),
        ),
        diagnostics: RuntimeDetectionDiagnostics.detected(
          source: RuntimeDetectionSource.rtlGetVersion,
          versionInfo: const WindowsVersionInfo(
            majorVersion: 10,
            minorVersion: 0,
            buildNumber: 26200,
            isServer: false,
            productName: 'Windows 11 Pro',
          ),
        ),
      ),
      setupDependenciesOverride:
          ({
            required RuntimeCapabilities capabilities,
            RuntimeDetectionDiagnostics? runtimeDetectionDiagnostics,
          }) async {
            capturedCapabilities = capabilities;
            capturedDiagnostics = runtimeDetectionDiagnostics;
          },
      bootstrapPhasesOverride: () async {
        bootstrapPhasesRan = true;
      },
      initializeDesktopFeaturesOverride: (capabilities) async {
        desktopFeaturesInitialized = true;
      },
      resolveInitialRouteOverride: (_) => '/agent-actions',
    );

    final result = await initializer.initialize(const <String>[]);

    expect(result.initialRoute, '/agent-actions');
    expect(result.capabilities.mode, RuntimeMode.full);
    expect(capturedCapabilities?.mode, RuntimeMode.full);
    expect(capturedDiagnostics?.source, RuntimeDetectionSource.rtlGetVersion);
    expect(capturedDiagnostics?.versionInfo?.versionString, '10.0.26200');
    expect(bootstrapPhasesRan, isTrue);
    expect(desktopFeaturesInitialized, isTrue);
  });

  test('passes fallback failed diagnostics when runtime probe fails', () async {
    var capturedCapabilities = null as RuntimeCapabilities?;
    var capturedDiagnostics = null as RuntimeDetectionDiagnostics?;

    final initializer = AppInitializer(
      runtimeProbe: _FakeWindowsRuntimeProbe(
        result: Failure<WindowsVersionInfo, Exception>(Exception('probe failed')),
        diagnostics: RuntimeDetectionDiagnostics.failed(
          failureMessage: 'probe failed',
          rawOperatingSystemVersion: 'Windows mystery build',
        ),
      ),
      setupDependenciesOverride:
          ({
            required RuntimeCapabilities capabilities,
            RuntimeDetectionDiagnostics? runtimeDetectionDiagnostics,
          }) async {
            capturedCapabilities = capabilities;
            capturedDiagnostics = runtimeDetectionDiagnostics;
          },
      bootstrapPhasesOverride: () async {},
      initializeDesktopFeaturesOverride: (capabilities) async {},
    );

    final result = await initializer.initialize(const <String>[]);

    expect(result.capabilities.mode, RuntimeMode.degraded);
    expect(capturedCapabilities?.isDegraded, isTrue);
    expect(capturedDiagnostics?.source, RuntimeDetectionSource.detectionFailed);
    expect(capturedDiagnostics?.rawOperatingSystemVersion, 'Windows mystery build');
  });

  test('restores native window on autostart when runtime does not support window manager', () async {
    var nativeWindowRestored = false;

    final initializer = AppInitializer(
      runtimeProbe: _FakeWindowsRuntimeProbe(
        result: const Success(
          WindowsVersionInfo(
            majorVersion: 6,
            minorVersion: 1,
            buildNumber: 7601,
            isServer: false,
            productName: 'Windows 7',
          ),
        ),
      ),
      setupDependenciesOverride:
          ({
            required RuntimeCapabilities capabilities,
            RuntimeDetectionDiagnostics? runtimeDetectionDiagnostics,
          }) async {
            getIt.registerSingleton<IAppSettingsStore>(InMemoryAppSettingsStore());
            getIt.registerSingleton<INotificationService>(_FakeNotificationService());
          },
      bootstrapPhasesOverride: () async {},
      nativeWindowVisibilityFallback: () async {
        nativeWindowRestored = true;
      },
    );

    await initializer.initialize(const <String>[AppStrings.singleInstanceArgAutostart]);

    expect(nativeWindowRestored, isTrue);
  });

  test('does not restore native window on manual launch when runtime does not support window manager', () async {
    var nativeWindowRestored = false;

    final initializer = AppInitializer(
      runtimeProbe: _FakeWindowsRuntimeProbe(
        result: const Success(
          WindowsVersionInfo(
            majorVersion: 6,
            minorVersion: 1,
            buildNumber: 7601,
            isServer: false,
            productName: 'Windows 7',
          ),
        ),
      ),
      setupDependenciesOverride:
          ({
            required RuntimeCapabilities capabilities,
            RuntimeDetectionDiagnostics? runtimeDetectionDiagnostics,
          }) async {
            getIt.registerSingleton<IAppSettingsStore>(InMemoryAppSettingsStore());
            getIt.registerSingleton<INotificationService>(_FakeNotificationService());
          },
      bootstrapPhasesOverride: () async {},
      nativeWindowVisibilityFallback: () async {
        nativeWindowRestored = true;
      },
    );

    await initializer.initialize(const <String>[]);

    expect(nativeWindowRestored, isFalse);
  });

  group('resolveStartupWindowPreferences', () {
    test('should not start minimized on manual launch even when preference is enabled', () async {
      final settingsStore = InMemoryAppSettingsStore({
        AppSettingsKeys.startMinimized: true,
      });

      final preferences = resolveStartupWindowPreferences(
        settingsStore,
      );

      expect(preferences.startMinimized, isFalse);
    });

    test('should start minimized only on autostart launch with tray support', () async {
      final settingsStore = InMemoryAppSettingsStore({
        AppSettingsKeys.startMinimized: true,
      });

      final preferences = resolveStartupWindowPreferences(
        settingsStore,
        isAutostartLaunch: true,
      );

      expect(preferences.startMinimized, isTrue);
    });

    test('should not start minimized on autostart launch without tray support', () async {
      final settingsStore = InMemoryAppSettingsStore({
        AppSettingsKeys.startMinimized: true,
      });

      final preferences = resolveStartupWindowPreferences(
        settingsStore,
        canStartMinimized: false,
        isAutostartLaunch: true,
      );

      expect(preferences.startMinimized, isFalse);
    });
  });

  test('showNativeRuntimeWindow invokes native runtime showWindow method', () async {
    const channel = MethodChannel('plug_agente/runtime');
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      capturedCall = call;
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );

    await showNativeRuntimeWindow();

    expect(capturedCall?.method, 'showWindow');
  });

  test('bootstrap source should not invoke PrepareElevatedActionRunner', () {
    final initializerSource = File(
      p.join('lib', 'presentation', 'boot', 'app_initializer.dart'),
    ).readAsStringSync();
    final agentActionsSource = File(
      p.join('lib', 'application', 'bootstrap', 'agent_actions_boot_phases.dart'),
    ).readAsStringSync();

    expect(initializerSource.contains('PrepareElevatedActionRunner'), isFalse);
    expect(initializerSource.contains('prepareElevatedActionRunner'), isFalse);
    expect(agentActionsSource.contains('_refreshElevatedActionRunnerReadiness'), isTrue);
  });

  test('deferred bootstrap source starts automatic update checks after agent actions', () {
    final deferredSource = File(
      p.join('lib', 'application', 'bootstrap', 'deferred_boot_phase_runner.dart'),
    ).readAsStringSync();
    final desktopSource = File(
      p.join('lib', 'presentation', 'boot', 'desktop_shell_bootstrap.dart'),
    ).readAsStringSync();

    expect(deferredSource.contains('_startAutomaticUpdateChecks'), isTrue);
    expect(
      RegExp(
        r'Future<DeferredBootPhaseOutcome> run\(\)[\s\S]*_startAutomaticUpdateChecks',
      ).hasMatch(deferredSource),
      isTrue,
    );
    expect(desktopSource.contains('startAutomaticChecks'), isFalse);
  });

  test('runtime guard stays starting until deferred bootstrap when phases are not overridden', () async {
    final guard = AgentActionRuntimeStateGuard();
    getIt.registerSingleton<AgentActionRuntimeStateGuard>(guard);

    final initializer = AppInitializer(
      runtimeProbe: _FakeWindowsRuntimeProbe(
        result: const Success(
          WindowsVersionInfo(
            majorVersion: 10,
            minorVersion: 0,
            buildNumber: 26200,
            isServer: false,
            productName: 'Windows 11 Pro',
          ),
        ),
      ),
      setupDependenciesOverride:
          ({
            required RuntimeCapabilities capabilities,
            RuntimeDetectionDiagnostics? runtimeDetectionDiagnostics,
          }) async {},
      initializeDesktopFeaturesOverride: (capabilities) async {},
      agentActionsBootPhases: _RecordingAgentActionsBootPhases(
        onDeferredScheduler: () {
          expect(guard.snapshot.status, AgentActionSubsystemStatus.starting);
        },
      ),
    );

    final bootstrapData = await initializer.initialize(const <String>[]);
    expect(guard.snapshot.status, AgentActionSubsystemStatus.starting);
    expect(bootstrapData.runDeferredBootstrap, isNotNull);

    await bootstrapData.runDeferredBootstrap!();
    expect(guard.snapshot.status, AgentActionSubsystemStatus.ready);
  });
}

class _RecordingAgentActionsBootPhases implements AgentActionsBootPhasesContract {
  _RecordingAgentActionsBootPhases({this.onDeferredScheduler});

  final void Function()? onDeferredScheduler;

  @override
  Future<void> runCritical() async {}

  @override
  Future<void> runDeferredMaintenance() async {}

  @override
  Future<bool> startSchedulerAndDispatchAppStart() async {
    onDeferredScheduler?.call();
    return true;
  }
}

class _FakeWindowsRuntimeProbe implements IWindowsRuntimeProbe {
  _FakeWindowsRuntimeProbe({
    required this.result,
    this.diagnostics,
  });

  final Result<WindowsVersionInfo> result;

  final RuntimeDetectionDiagnostics? diagnostics;

  @override
  RuntimeDetectionDiagnostics? get lastDiagnostics => diagnostics;

  @override
  Future<Result<WindowsVersionInfo>> detect() async => result;
}

class _FakeNotificationService implements INotificationService {
  @override
  Future<Result<void>> cancel(int id) async => const Success(unit);

  @override
  Future<Result<void>> cancelAll() async => const Success(unit);

  @override
  Future<Result<void>> initialize() async => const Success(unit);

  @override
  Future<Result<void>> schedule({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async => const Success(unit);

  @override
  Future<Result<void>> show({
    required String title,
    required String body,
    String? payload,
  }) async => const Success(unit);
}
