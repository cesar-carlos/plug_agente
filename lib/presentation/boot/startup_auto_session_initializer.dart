import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:plug_agente/application/bootstrap/deferred_boot_phase_outcome.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/application/services/startup_session_orchestrator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/presentation/adapters/startup_session_ports_adapter.dart';
import 'package:plug_agente/presentation/boot/hub_recovery_auth_bridge_wiring.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:provider/provider.dart';

class StartupAutoSessionInitializer extends StatefulWidget {
  const StartupAutoSessionInitializer({
    required this.hubSessionCoordinator,
    required this.child,
    this.runDeferredBootstrapBeforeConnect,
    this.defaultServerUrl = 'https://api.example.com',
    super.key,
  });

  final HubSessionCoordinator hubSessionCoordinator;
  final Widget child;
  final Future<DeferredBootPhaseOutcome> Function()? runDeferredBootstrapBeforeConnect;
  final String defaultServerUrl;

  @override
  State<StartupAutoSessionInitializer> createState() => _StartupAutoSessionInitializerState();
}

class _StartupAutoSessionInitializerState extends State<StartupAutoSessionInitializer> {
  ConnectionProvider? _connectionProvider;
  AuthProvider? _authProvider;
  ConfigProvider? _configProvider;
  String? _lastOdbcSignature;
  String? _lastBootstrapFailedSignature;
  bool _startupFlowHandled = false;
  bool _startupFlowRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProviders();
    });
  }

  @override
  void dispose() {
    _configProvider?.removeListener(_onConfigStateChanged);
    super.dispose();
  }

  void _initializeProviders() {
    if (!mounted) {
      return;
    }
    final connectionProvider = context.read<ConnectionProvider>();
    final authProvider = context.read<AuthProvider>();
    final configProvider = context.read<ConfigProvider>();

    _connectionProvider = connectionProvider;
    _authProvider = authProvider;
    _configProvider = configProvider;

    connectionProvider.setConfigProvider(configProvider);
    wireHubRecoveryAuthBridge(
      authProvider: authProvider,
      connectionProvider: connectionProvider,
      sessionCoordinator: widget.hubSessionCoordinator,
    );

    configProvider.removeListener(_onConfigStateChanged);
    configProvider.addListener(_onConfigStateChanged);

    _syncDbIndicatorWithConfig();
    unawaited(_runStartupFlow());
  }

  void _onConfigStateChanged() {
    _syncDbIndicatorWithConfig();
    if (_startupFlowHandled) {
      return;
    }
    final signature = _startupConfigSignature(_configProvider?.currentConfig);
    if (_lastBootstrapFailedSignature != null && signature == _lastBootstrapFailedSignature) {
      return;
    }
    unawaited(_runStartupFlow());
  }

  Future<void> _runStartupFlow() async {
    if (!mounted || _startupFlowHandled || _startupFlowRunning) {
      return;
    }

    _startupFlowRunning = true;
    try {
      final connectionProvider = _connectionProvider;
      final authProvider = _authProvider;
      final configProvider = _configProvider;
      if (connectionProvider == null || authProvider == null || configProvider == null) {
        return;
      }

      final currentConfig = configProvider.currentConfig;
      final signature = _startupConfigSignature(currentConfig);
      if (_lastBootstrapFailedSignature != null && signature == _lastBootstrapFailedSignature) {
        return;
      }

      final result =
          await StartupSessionOrchestrator(
            hubSessionCoordinator: widget.hubSessionCoordinator,
            ports: startupSessionPortsFromProviders(
              configProvider: configProvider,
              authProvider: authProvider,
              connectionProvider: connectionProvider,
            ),
          ).run(
            runDeferredBootstrapBeforeConnect: widget.runDeferredBootstrapBeforeConnect,
            defaultServerUrl: widget.defaultServerUrl,
          );

      if (result == StartupSessionFlowResult.completed || result == StartupSessionFlowResult.deferredBootstrapFailed) {
        _markStartupFlowHandled();
      } else if (result == StartupSessionFlowResult.bootstrapFailed) {
        _lastBootstrapFailedSignature = signature;
      }
    } finally {
      _startupFlowRunning = false;
    }
  }

  void _syncDbIndicatorWithConfig() {
    final configProvider = _configProvider;
    final connectionProvider = _connectionProvider;
    if (configProvider == null || connectionProvider == null) {
      return;
    }
    if (configProvider.currentConfig == null) {
      return;
    }
    final signature = configProvider.getConnectionString();
    if (_lastOdbcSignature != null && _lastOdbcSignature!.isNotEmpty && signature != _lastOdbcSignature) {
      connectionProvider.setDbConnectionIndicator(false);
    }
    _lastOdbcSignature = signature;
  }

  void _markStartupFlowHandled() {
    if (_startupFlowHandled) {
      return;
    }
    _startupFlowHandled = true;
    AppLogger.debug('Startup auth/socket auto-flow completed');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String? _startupConfigSignature(Config? config) {
  if (config == null) {
    return null;
  }
  return [
    config.id,
    config.serverUrl.trim(),
    config.agentId.trim(),
    config.authToken?.trim() ?? '',
    config.refreshToken?.trim() ?? '',
    config.authUsername?.trim() ?? '',
    config.authPassword?.trim() ?? '',
  ].join('|');
}
