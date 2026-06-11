import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/bootstrap/agent_actions_boot_phases.dart';
import 'package:plug_agente/application/bootstrap/deferred_boot_phase_outcome.dart';
import 'package:plug_agente/application/bootstrap/deferred_boot_phase_runner.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/routes/deep_link_service.dart';
import 'package:plug_agente/core/runtime/app_uptime.dart';
import 'package:plug_agente/core/runtime/i_windows_runtime_probe.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/runtime/runtime_mode.dart';
import 'package:plug_agente/core/runtime/runtime_policy_evaluator.dart';
import 'package:plug_agente/core/utils/launch_args.dart';
import 'package:plug_agente/presentation/boot/app_bootstrap_data.dart';
import 'package:plug_agente/presentation/boot/desktop_shell_bootstrap.dart';

export 'package:plug_agente/presentation/boot/desktop_shell_bootstrap.dart'
    show
        NativeWindowVisibilityFallback,
        StartupWindowPreferences,
        resolveStartupWindowPreferences,
        showNativeRuntimeWindow;

typedef SetupDependenciesOverride =
    Future<void> Function({
      required RuntimeCapabilities capabilities,
      RuntimeDetectionDiagnostics? runtimeDetectionDiagnostics,
    });

typedef BootstrapPhasesOverride = Future<void> Function();

typedef InitializeDesktopFeaturesOverride =
    Future<void> Function(
      RuntimeCapabilities capabilities,
    );

typedef ResolveInitialRouteOverride = String? Function(List<String> args);

class AppInitializer {
  AppInitializer({
    required this.runtimeProbe,
    this.setupDependenciesOverride,
    this.bootstrapPhasesOverride,
    this.initializeDesktopFeaturesOverride,
    this.resolveInitialRouteOverride,
    NativeWindowVisibilityFallback? nativeWindowVisibilityFallback,
    AgentActionsBootPhasesContract? agentActionsBootPhases,
  }) : _nativeWindowVisibilityFallback = nativeWindowVisibilityFallback,
       _agentActionsBootPhases = agentActionsBootPhases ?? const AgentActionsBootPhases();

  final IWindowsRuntimeProbe runtimeProbe;
  final SetupDependenciesOverride? setupDependenciesOverride;
  final BootstrapPhasesOverride? bootstrapPhasesOverride;
  final InitializeDesktopFeaturesOverride? initializeDesktopFeaturesOverride;
  final ResolveInitialRouteOverride? resolveInitialRouteOverride;
  final NativeWindowVisibilityFallback? _nativeWindowVisibilityFallback;
  final AgentActionsBootPhasesContract _agentActionsBootPhases;
  RuntimeDetectionDiagnostics? _lastRuntimeDetectionDiagnostics;
  RuntimeCapabilities? _lastRuntimeCapabilities;
  bool _isAutostartLaunch = false;

  Future<AppBootstrapData> initialize(List<String> args) async {
    AppUptime.markStarted();
    await AppEnvironment.loadOptional();
    _isAutostartLaunch = isAutostartLaunch(args);

    final capabilities = await _resolveRuntimeCapabilities();
    _lastRuntimeCapabilities = capabilities;
    await (setupDependenciesOverride ?? setupDependencies)(
      capabilities: capabilities,
      runtimeDetectionDiagnostics: _lastRuntimeDetectionDiagnostics,
    );
    _markAgentActionsSubsystemStarting();
    final usesDeferredBootstrap = bootstrapPhasesOverride == null;
    try {
      if (bootstrapPhasesOverride case final BootstrapPhasesOverride override) {
        await override();
      } else {
        await _agentActionsBootPhases.runCritical();
      }
    } finally {
      if (!usesDeferredBootstrap) {
        _markAgentActionsSubsystemReady();
      }
    }
    final initialRoute = resolveInitialRouteOverride?.call(args) ?? _resolveInitialRoute(args);
    await (initializeDesktopFeaturesOverride ?? _initializeDesktopFeatures)(capabilities);

    return AppBootstrapData(
      capabilities: capabilities,
      initialRoute: initialRoute,
      runDeferredBootstrap: usesDeferredBootstrap ? _runDeferredBootstrapPhases : null,
    );
  }

  Future<RuntimeCapabilities> _resolveRuntimeCapabilities() async {
    final probe = runtimeProbe;
    const evaluator = RuntimePolicyEvaluator();

    final versionResult = await probe.detect();
    final capabilities = versionResult.fold(
      (versionInfo) {
        _lastRuntimeDetectionDiagnostics = probe.lastDiagnostics;
        developer.log(
          'Windows version detected: $versionInfo',
          name: 'app_initializer',
          level: 800,
        );
        if (_lastRuntimeDetectionDiagnostics case final RuntimeDetectionDiagnostics diagnostics) {
          developer.log(
            'Runtime detection details: source=${diagnostics.sourceName} '
            'version=${versionInfo.versionString} isServer=${versionInfo.isServer} '
            'product=${versionInfo.productName ?? "-"}',
            name: 'app_initializer',
            level: 800,
          );
        }
        return evaluator.evaluate(versionInfo);
      },
      (failure) {
        _lastRuntimeDetectionDiagnostics =
            probe.lastDiagnostics ??
            RuntimeDetectionDiagnostics.failed(
              failureMessage: failure.toString(),
            );
        developer.log(
          'Failed to detect Windows version, using degraded safe mode: $failure',
          name: 'app_initializer',
          level: 900,
        );
        return RuntimeCapabilities.degraded(
          reasons: <String>[
            'Falha ao detectar versão do Windows com confiança',
            'Fallback seguro aplicado para evitar crashes de plugins desktop',
          ],
        );
      },
    );

    developer.log(
      'Runtime mode: ${capabilities.mode.displayName}',
      name: 'app_initializer',
      level: 800,
    );

    if (capabilities.degradationReasons.isNotEmpty) {
      developer.log(
        'Degradation reasons: ${capabilities.degradationReasons.join(", ")}',
        name: 'app_initializer',
        level: 800,
      );
    }

    return capabilities;
  }

  Future<DeferredBootPhaseOutcome> _runDeferredBootstrapPhases() {
    return DeferredBootPhaseRunner(
      agentActionsBootPhases: _agentActionsBootPhases,
      capabilities: _lastRuntimeCapabilities,
    ).run();
  }

  String? _resolveInitialRoute(List<String> args) {
    final deepLinkService = DeepLinkService();
    final initialLink = deepLinkService.getInitialLink(args);
    return initialLink != null ? deepLinkService.deepLinkToRoute(initialLink) : null;
  }

  void _markAgentActionsSubsystemStarting() {
    if (!getIt.isRegistered<AgentActionRuntimeStateGuard>()) {
      return;
    }
    getIt<AgentActionRuntimeStateGuard>().markStarting(reason: AgentActionRuntimeStateConstants.bootstrapReason);
  }

  void _markAgentActionsSubsystemReady() {
    if (!getIt.isRegistered<AgentActionRuntimeStateGuard>()) {
      return;
    }
    getIt<AgentActionRuntimeStateGuard>().markReady();
  }

  Future<void> _initializeDesktopFeatures(
    RuntimeCapabilities capabilities,
  ) async {
    await DesktopShellBootstrap(
      isAutostartLaunch: _isAutostartLaunch,
      nativeWindowVisibilityFallback: _nativeWindowVisibilityFallback,
    ).initialize(capabilities);
  }
}
