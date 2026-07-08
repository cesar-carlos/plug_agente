import 'package:plug_agente/application/bootstrap/agent_actions_boot_phases.dart';
import 'package:plug_agente/application/bootstrap/app_bootstrap_data.dart';
import 'package:plug_agente/application/bootstrap/app_bootstrap_orchestrator.dart';
import 'package:plug_agente/application/bootstrap/deferred_boot_phase_runner_dependencies.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/i_windows_runtime_probe.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/noop_tray_manager_service.dart';
import 'package:plug_agente/core/services/window_manager_service.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/presentation/boot/desktop_shell_bootstrap.dart';

export 'package:plug_agente/application/bootstrap/app_bootstrap_data.dart';
export 'package:plug_agente/application/bootstrap/app_bootstrap_orchestrator.dart'
    show
        AppBootstrapOrchestrator,
        BootstrapPhasesOverride,
        EnsureStartupLaunchConfigurationAtBootOverride,
        InitializeDesktopFeaturesOverride,
        ResolveInitialRouteOverride,
        SetupDependenciesOverride;
export 'package:plug_agente/presentation/boot/desktop_shell_bootstrap.dart'
    show
        NativeWindowVisibilityFallback,
        StartupWindowPreferences,
        resolveStartupWindowPreferences,
        showNativeRuntimeWindow;

Future<void> _defaultInitializeDesktopFeatures(
  RuntimeCapabilities capabilities,
  bool isAutostartLaunch, {
  NativeWindowVisibilityFallback? nativeWindowVisibilityFallback,
  DesktopShellBootstrapDependencies? desktopShellBootstrapDependencies,
}) async {
  await DesktopShellBootstrap(
    isAutostartLaunch: isAutostartLaunch,
    dependencies: desktopShellBootstrapDependencies ?? _createDesktopShellBootstrapDependencies(),
    nativeWindowVisibilityFallback: nativeWindowVisibilityFallback,
  ).initialize(capabilities);
}

DesktopShellBootstrapDependencies _createDesktopShellBootstrapDependencies() {
  return DesktopShellBootstrapDependencies(
    settingsStore: getIt<IAppSettingsStore>(),
    trayService: getIt.isRegistered<ITrayService>() ? getIt<ITrayService>() : NoopTrayManagerService(),
    notificationService: getIt<INotificationService>(),
    resolveWindowManager: getIt.isRegistered<WindowManagerService>() ? getIt<WindowManagerService>() : null,
  );
}

class AppInitializer {
  AppInitializer({
    required this.runtimeProbe,
    SetupDependenciesOverride? setupDependenciesOverride,
    BootstrapPhasesOverride? bootstrapPhasesOverride,
    InitializeDesktopFeaturesOverride? initializeDesktopFeaturesOverride,
    ResolveInitialRouteOverride? resolveInitialRouteOverride,
    EnsureStartupLaunchConfigurationAtBootOverride? ensureStartupLaunchConfigurationOverride,
    NativeWindowVisibilityFallback? nativeWindowVisibilityFallback,
    AgentActionsBootPhasesContract? agentActionsBootPhases,
    DeferredBootPhaseRunnerDependencies? deferredBootPhaseRunnerDependencies,
    DesktopShellBootstrapDependencies? desktopShellBootstrapDependencies,
  }) : _orchestrator = AppBootstrapOrchestrator(
         runtimeProbe: runtimeProbe,
         setupDependenciesOverride: setupDependenciesOverride,
         bootstrapPhasesOverride: bootstrapPhasesOverride,
         initializeDesktopFeaturesOverride:
             initializeDesktopFeaturesOverride ??
             ((capabilities, isAutostartLaunch) => _defaultInitializeDesktopFeatures(
               capabilities,
               isAutostartLaunch,
               nativeWindowVisibilityFallback: nativeWindowVisibilityFallback,
               desktopShellBootstrapDependencies: desktopShellBootstrapDependencies,
             )),
         resolveInitialRouteOverride: resolveInitialRouteOverride,
         ensureStartupLaunchConfigurationOverride: ensureStartupLaunchConfigurationOverride,
         agentActionsBootPhases: agentActionsBootPhases,
         deferredBootPhaseRunnerDependencies: deferredBootPhaseRunnerDependencies,
       );

  final IWindowsRuntimeProbe runtimeProbe;
  final AppBootstrapOrchestrator _orchestrator;

  Future<AppBootstrapData> initialize(List<String> args) => _orchestrator.run(args);
}
