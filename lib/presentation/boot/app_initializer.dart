import 'dart:async';
import 'dart:developer' as developer;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/services/agent_action_captured_output_periodic_purge.dart';
import 'package:plug_agente/application/services/agent_action_execution_periodic_purge.dart';
import 'package:plug_agente/application/services/agent_action_remote_audit_periodic_purge.dart';
import 'package:plug_agente/application/services/elevated_bridge_artifacts_periodic_purge.dart';
import 'package:plug_agente/application/services/rpc_idempotency_cache_periodic_purge.dart';
import 'package:plug_agente/application/use_cases/cleanup_agent_action_captured_output.dart';
import 'package:plug_agente/application/use_cases/cleanup_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_agent_action_remote_audit.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_elevated_bridge_artifacts.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_rpc_idempotency_cache.dart';
import 'package:plug_agente/application/use_cases/reconcile_agent_action_executions.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/core/constants/window_constraints.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/routes/deep_link_service.dart';
import 'package:plug_agente/core/runtime/app_uptime.dart';
import 'package:plug_agente/core/runtime/i_windows_runtime_probe.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/runtime/runtime_mode.dart';
import 'package:plug_agente/core/runtime/runtime_policy_evaluator.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/core/services/window_manager_service.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/presentation/boot/app_bootstrap_data.dart';

typedef StartupWindowPreferences = ({
  bool startMinimized,
  bool minimizeToTray,
  bool closeToTray,
});

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

@visibleForTesting
StartupWindowPreferences resolveStartupWindowPreferences(
  IAppSettingsStore settingsStore, {
  bool canStartMinimized = true,
}) {
  return (
    startMinimized: canStartMinimized && (settingsStore.getBool(AppSettingsKeys.startMinimized) ?? false),
    minimizeToTray: settingsStore.getBool(AppSettingsKeys.minimizeToTray) ?? true,
    closeToTray: settingsStore.getBool(AppSettingsKeys.closeToTray) ?? true,
  );
}

class AppInitializer {
  AppInitializer({
    required this.runtimeProbe,
    this.setupDependenciesOverride,
    this.bootstrapPhasesOverride,
    this.initializeDesktopFeaturesOverride,
    this.resolveInitialRouteOverride,
  });

  final IWindowsRuntimeProbe runtimeProbe;
  final SetupDependenciesOverride? setupDependenciesOverride;
  final BootstrapPhasesOverride? bootstrapPhasesOverride;
  final InitializeDesktopFeaturesOverride? initializeDesktopFeaturesOverride;
  final ResolveInitialRouteOverride? resolveInitialRouteOverride;
  RuntimeDetectionDiagnostics? _lastRuntimeDetectionDiagnostics;

  Future<AppBootstrapData> initialize(List<String> args) async {
    AppUptime.markStarted();
    await AppEnvironment.loadOptional();

    final capabilities = await _resolveRuntimeCapabilities();
    await (setupDependenciesOverride ?? setupDependencies)(
      capabilities: capabilities,
      runtimeDetectionDiagnostics: _lastRuntimeDetectionDiagnostics,
    );
    _markAgentActionsSubsystemStarting();
    try {
      if (bootstrapPhasesOverride case final BootstrapPhasesOverride override) {
        await override();
      } else {
        await _runBootstrapPhases();
      }
    } finally {
      _markAgentActionsSubsystemReady();
    }
    final initialRoute = resolveInitialRouteOverride?.call(args) ?? _resolveInitialRoute(args);
    await (initializeDesktopFeaturesOverride ?? _initializeDesktopFeatures)(capabilities);
    if (bootstrapPhasesOverride == null) {
      await _dispatchAppStartAgentActions();
    }

    return AppBootstrapData(
      capabilities: capabilities,
      initialRoute: initialRoute,
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

  Future<void> _runBootstrapPhases() async {
    _refreshElevatedActionRunnerReadiness();
    await _reconcileAgentActionExecutions();
    await _purgeStaleElevatedBridgeArtifacts();
    await _clearOldAgentActionCapturedOutput();
    await _purgeOldAgentActionExecutions();
    await _purgeExpiredRpcIdempotencyCache();
    _startRpcIdempotencyPeriodicPurge();
    await _purgeExpiredAgentActionRemoteAudit();
    _startAgentActionCapturedOutputPeriodicPurge();
    _startAgentActionExecutionPeriodicPurge();
    _startAgentActionRemoteAuditPeriodicPurge();
    _startElevatedBridgeArtifactsPeriodicPurge();

    // Warm up ODBC connection pool if connection string is configured
    await _warmUpConnectionPool();
    await _startAgentActionScheduler();
  }

  String? _resolveInitialRoute(List<String> args) {
    final deepLinkService = DeepLinkService();
    final initialLink = deepLinkService.getInitialLink(args);
    return initialLink != null ? deepLinkService.deepLinkToRoute(initialLink) : null;
  }

  void _refreshElevatedActionRunnerReadiness() {
    if (!getIt.isRegistered<ElevatedActionRunnerReadinessService>()) {
      return;
    }
    getIt<ElevatedActionRunnerReadinessService>().refresh(getIt<GlobalStorageContext>());
  }

  Future<void> _purgeStaleElevatedBridgeArtifacts() async {
    if (!getIt.isRegistered<CleanupExpiredElevatedBridgeArtifacts>()) {
      return;
    }

    try {
      final result = await getIt<CleanupExpiredElevatedBridgeArtifacts>()();
      result.fold(
        (int count) {
          if (count > 0) {
            developer.log(
              'Purged $count stale elevated bridge artifact file(s) during bootstrap',
              name: 'app_initializer',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            'Failed to purge stale elevated bridge artifacts during bootstrap (continuing without)',
            name: 'app_initializer',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to purge stale elevated bridge artifacts during bootstrap (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _startElevatedBridgeArtifactsPeriodicPurge() {
    if (!getIt.isRegistered<ElevatedBridgeArtifactsPeriodicPurge>()) {
      return;
    }

    try {
      getIt<ElevatedBridgeArtifactsPeriodicPurge>().start();
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to start periodic elevated bridge artifact purge (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _reconcileAgentActionExecutions() async {
    try {
      final result = await getIt<ReconcileAgentActionExecutions>()();
      result.fold(
        (count) {
          if (count > 0) {
            developer.log(
              'Reconciled $count interrupted agent action execution(s) during bootstrap',
              name: 'app_initializer',
              level: 800,
            );
          }
        },
        (failure) {
          developer.log(
            'Failed to reconcile agent action executions during bootstrap (continuing without)',
            name: 'app_initializer',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to reconcile agent action executions during bootstrap (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _purgeExpiredRpcIdempotencyCache() async {
    try {
      final result = await getIt<CleanupExpiredRpcIdempotencyCache>()();
      result.fold(
        (int count) {
          if (count > 0) {
            developer.log(
              'Purged $count expired RPC idempotency cache row(s) during bootstrap',
              name: 'app_initializer',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            'Failed to purge expired RPC idempotency cache during bootstrap (continuing without)',
            name: 'app_initializer',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to purge expired RPC idempotency cache during bootstrap (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _startRpcIdempotencyPeriodicPurge() {
    try {
      getIt<RpcIdempotencyCachePeriodicPurge>().start();
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to start periodic RPC idempotency cache purge (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _purgeExpiredAgentActionRemoteAudit() async {
    try {
      final result = await getIt<CleanupExpiredAgentActionRemoteAudit>()();
      result.fold(
        (int count) {
          if (count > 0) {
            developer.log(
              'Purged $count old agent action remote audit row(s) during bootstrap',
              name: 'app_initializer',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            'Failed to purge old agent action remote audit rows during bootstrap (continuing without)',
            name: 'app_initializer',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to purge old agent action remote audit rows during bootstrap (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _startAgentActionRemoteAuditPeriodicPurge() {
    try {
      getIt<AgentActionRemoteAuditPeriodicPurge>().start();
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to start periodic agent action remote audit purge (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _clearOldAgentActionCapturedOutput() async {
    if (!getIt.isRegistered<CleanupAgentActionCapturedOutput>()) {
      return;
    }

    try {
      final result = await getIt<CleanupAgentActionCapturedOutput>()();
      result.fold(
        (int count) {
          if (count > 0) {
            developer.log(
              'Cleared captured output on $count agent action execution row(s) during bootstrap',
              name: 'app_initializer',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            'Failed to clear old agent action captured output during bootstrap (continuing without)',
            name: 'app_initializer',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to clear old agent action captured output during bootstrap (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _startAgentActionCapturedOutputPeriodicPurge() {
    if (!getIt.isRegistered<AgentActionCapturedOutputPeriodicPurge>()) {
      return;
    }

    try {
      getIt<AgentActionCapturedOutputPeriodicPurge>().start();
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to start periodic agent action captured output purge (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _purgeOldAgentActionExecutions() async {
    try {
      final result = await getIt<CleanupAgentActionExecutions>()();
      result.fold(
        (int count) {
          if (count > 0) {
            developer.log(
              'Purged $count old terminal agent action execution row(s) during bootstrap',
              name: 'app_initializer',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            'Failed to purge old agent action executions during bootstrap (continuing without)',
            name: 'app_initializer',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to purge old agent action executions during bootstrap (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _startAgentActionExecutionPeriodicPurge() {
    try {
      getIt<AgentActionExecutionPeriodicPurge>().start();
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to start periodic agent action execution history purge (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _warmUpConnectionPool() async {
    try {
      final configResult = await getIt<ActiveConfigResolver>().resolveActiveOrFallback(
        metadataOnly: true,
      );

      await configResult.fold(
        (agentConfig) async {
          if (agentConfig.connectionString.isEmpty) {
            developer.log(
              'Skipping pool warm-up: no connection string configured',
              name: 'app_initializer',
              level: 500,
            );
            return;
          }

          final pool = getIt<IConnectionPool>();
          if (pool is IConnectionPoolWarmUp) {
            final warmUpPool = pool as IConnectionPoolWarmUp;
            final warmUpResult = await warmUpPool.warmUp(agentConfig.connectionString);
            warmUpResult.fold(
              (_) {},
              (Object failure) {
                developer.log(
                  'Pool warm-up cleanup failed (continuing without)',
                  name: 'app_initializer',
                  level: 900,
                  error: failure,
                );
              },
            );
          }
        },
        (failure) {
          developer.log(
            'Skipping pool warm-up: config not available',
            name: 'app_initializer',
            level: 500,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Pool warm-up failed (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _startAgentActionScheduler() async {
    try {
      final scheduler = getIt<AgentActionTriggerScheduler>();
      final startResult = await scheduler.start();
      startResult.fold(
        (snapshot) {
          developer.log(
            'Agent action scheduler started '
            '(scheduled: ${snapshot.scheduledCount}, skipped: ${snapshot.skippedCount}, '
            'issues: ${snapshot.issues.length})',
            name: 'app_initializer',
            level: snapshot.hasIssues ? 900 : 800,
          );
        },
        (failure) {
          scheduler.stop();
          developer.log(
            'Failed to start agent action scheduler (continuing without temporal actions)',
            name: 'app_initializer',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      try {
        getIt<AgentActionTriggerScheduler>().stop();
      } on Object {
        // Scheduler may not be registered; bootstrap continues without agent actions.
      }
      developer.log(
        'Failed to initialize agent action scheduler (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _dispatchAppStartAgentActions() async {
    final scheduler = getIt<AgentActionTriggerScheduler>();
    try {
      final result = await scheduler.dispatchAppStartTriggers();
      result.fold(
        (count) {
          if (count > 0) {
            developer.log(
              'Dispatched $count app-start agent action trigger(s)',
              name: 'app_initializer',
              level: 800,
            );
          }
        },
        (failure) {
          developer.log(
            'Failed to dispatch app-start agent action triggers',
            name: 'app_initializer',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to dispatch app-start agent action triggers',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
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
    WindowManagerService? windowManagerService;

    if (capabilities.supportsWindowManager) {
      windowManagerService = await _initializeWindowManager(capabilities);
    }

    if (capabilities.supportsTray && windowManagerService != null) {
      await _initializeTray(windowManagerService);
    } else if (capabilities.supportsTray) {
      developer.log(
        'Tray manager skipped because window manager is unavailable',
        name: 'app_initializer',
        level: 800,
      );
    } else {
      developer.log(
        'Tray manager not available in degraded mode',
        name: 'app_initializer',
        level: 800,
      );
    }

    await _initializeNotifications();
    await _initializeAutoUpdate(capabilities);
  }

  Future<void> _initializeAutoUpdate(
    RuntimeCapabilities capabilities,
  ) async {
    if (!capabilities.supportsAutoUpdate) {
      developer.log(
        'Auto-update skipped: not supported in current runtime mode',
        name: 'app_initializer',
        level: 800,
      );
      return;
    }

    try {
      final orchestrator = getIt<IAutoUpdateOrchestrator>();
      await orchestrator.startAutomaticChecks();
      if (orchestrator.isAvailable) {
        developer.log(
          'Auto-update initialized and automatic check scheduling started',
          name: 'app_initializer',
          level: 800,
        );
      }
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to initialize auto-update (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<WindowManagerService?> _initializeWindowManager(
    RuntimeCapabilities capabilities,
  ) async {
    try {
      final windowManagerService = WindowManagerService();
      final minSize = WindowConstraints.getMainWindowMinSize();
      const initialSize = Size(1200, 800);

      final prefs = getIt<IAppSettingsStore>();
      final preferences = resolveStartupWindowPreferences(
        prefs,
        canStartMinimized: capabilities.supportsTray,
      );

      await windowManagerService.initialize(
        size: initialSize,
        minimumSize: minSize,
        startMinimized: preferences.startMinimized,
      );

      getIt.registerSingleton<WindowManagerService>(windowManagerService);
      getIt.registerSingleton<IWindowManagerService>(windowManagerService);

      developer.log(
        'Window manager initialized '
        '(startMinimized: ${preferences.startMinimized})',
        name: 'app_initializer',
        level: 800,
      );
      return windowManagerService;
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to initialize window manager (degraded mode will continue)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _initializeTray(
    WindowManagerService windowManagerService,
  ) async {
    try {
      final trayService = getIt<ITrayService>();
      await trayService.initialize(
        onMenuAction: (action) async {
          switch (action) {
            case TrayMenuAction.show:
              await windowManagerService.show();
            case TrayMenuAction.exit:
              trayService.dispose();
              await windowManagerService.close();
          }
        },
      );

      final prefs = getIt<IAppSettingsStore>();
      final preferences = resolveStartupWindowPreferences(prefs);

      windowManagerService
        ..setMinimizeToTray(value: preferences.minimizeToTray)
        ..setCloseToTray(value: preferences.closeToTray);

      developer.log(
        'Tray behaviors configured '
        '(minimize: ${preferences.minimizeToTray}, '
        'close: ${preferences.closeToTray})',
        name: 'app_initializer',
        level: 800,
      );

      developer.log(
        'Tray manager initialized',
        name: 'app_initializer',
        level: 800,
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to initialize tray manager (continuing without tray)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      final result = await getIt<INotificationService>().initialize();
      result.fold(
        (_) {
          developer.log(
            'Notification service initialized',
            name: 'app_initializer',
            level: 800,
          );
        },
        (failure) {
          developer.log(
            'Failed to initialize notification service (continuing without)',
            name: 'app_initializer',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to initialize notification service (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
