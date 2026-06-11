import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:plug_agente/application/bootstrap/deferred_boot_phase_outcome.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/utils/url_utils.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
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

    connectionProvider.setAuthProvider(authProvider);
    connectionProvider.setConfigProvider(configProvider);

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
    unawaited(_runStartupFlow());
  }

  Future<void> _runStartupFlow() async {
    if (!mounted || _startupFlowHandled || _startupFlowRunning) {
      return;
    }

    _startupFlowRunning = true;
    try {
      final deferredBootstrap = widget.runDeferredBootstrapBeforeConnect;
      if (deferredBootstrap != null) {
        try {
          final outcome = await deferredBootstrap();
          if (outcome.shouldSkipHubAutoConnect) {
            AppLogger.warning(
              'Skipping Hub auto-connect after critical deferred bootstrap failure',
            );
            _markStartupFlowHandled();
            return;
          }
        } on Object catch (error, stackTrace) {
          AppLogger.error(
            'Deferred bootstrap failed before Hub auto-connect',
            error,
            stackTrace,
          );
          _markStartupFlowHandled();
          return;
        }
      }

      if (!mounted || _startupFlowHandled) {
        return;
      }

      await _attemptStartupLoginAndConnect();
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

  Future<void> _attemptStartupLoginAndConnect() async {
    if (!mounted || _startupFlowHandled) {
      return;
    }

    final configProvider = _configProvider;
    final connectionProvider = _connectionProvider;
    final authProvider = _authProvider;
    if (configProvider == null || connectionProvider == null || authProvider == null) {
      return;
    }

    if (configProvider.isLoading) {
      return;
    }
    if (connectionProvider.isConnected ||
        connectionProvider.status == ConnectionStatus.connecting ||
        connectionProvider.status == ConnectionStatus.negotiating ||
        connectionProvider.status == ConnectionStatus.reconnecting) {
      _markStartupFlowHandled();
      return;
    }

    final config = configProvider.currentConfig;
    if (config == null) {
      _markStartupFlowHandled();
      return;
    }

    final startupContext = _buildStartupContext(config);
    if (startupContext == null) {
      _markStartupFlowHandled();
      return;
    }

    final bootstrapResult = await widget.hubSessionCoordinator.bootstrapAutoSession(
      configId: startupContext.configId,
      serverUrl: startupContext.serverUrl,
      agentId: startupContext.agentId,
    );

    var shouldStop = false;
    AuthToken? startupToken;
    bootstrapResult.fold(
      (session) {
        startupToken = session.token;
        authProvider.restoreToken(
          session.token,
          configId: startupContext.configId,
          silent: true,
        );
      },
      (failure) {
        if (failure is domain_errors.Failure && failure.isTransient) {
          connectionProvider.startPersistentHubRecovery(
            configId: startupContext.configId,
            serverUrl: startupContext.serverUrl,
            agentId: startupContext.agentId,
          );
        } else {
          authProvider.setRecoveryError(failure.toDisplayMessage());
        }
        _markStartupFlowHandled();
        shouldStop = true;
      },
    );
    if (shouldStop || startupToken == null) {
      return;
    }

    final connectResult = await connectionProvider.connect(
      startupContext.serverUrl,
      startupContext.agentId,
      configId: startupContext.configId,
      authToken: startupToken!.token,
      recoverOnFailure: true,
    );
    if (connectResult.isSuccess() ||
        connectionProvider.status == ConnectionStatus.reconnecting ||
        connectionProvider.isReconnecting) {
      _markStartupFlowHandled();
    }
  }

  _StartupContext? _buildStartupContext(Config config) {
    final serverUrl = normalizeServerUrl(config.serverUrl);
    final agentId = config.agentId.trim();

    if (serverUrl.isEmpty || serverUrl.toLowerCase() == widget.defaultServerUrl || agentId.isEmpty) {
      return null;
    }

    final authToken = config.authToken?.trim();
    final refreshToken = config.refreshToken?.trim();
    final hasAuthTokenPair =
        authToken != null && authToken.isNotEmpty && refreshToken != null && refreshToken.isNotEmpty;
    final authUsername = config.authUsername?.trim();
    final authPassword = config.authPassword?.trim();
    final hasAuthCredentials =
        authUsername != null && authUsername.isNotEmpty && authPassword != null && authPassword.isNotEmpty;

    if (!hasAuthTokenPair && !hasAuthCredentials) {
      return null;
    }

    return _StartupContext(
      configId: config.id,
      serverUrl: serverUrl,
      agentId: agentId,
    );
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

class _StartupContext {
  const _StartupContext({
    required this.configId,
    required this.serverUrl,
    required this.agentId,
  });

  final String configId;
  final String serverUrl;
  final String agentId;
}
