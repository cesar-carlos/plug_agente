import 'package:plug_agente/application/bootstrap/deferred_boot_phase_outcome.dart';
import 'package:plug_agente/application/ports/startup_session_ports.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/application/state/hub_connection_display_state.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/utils/url_utils.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;

enum StartupSessionFlowResult {
  completed,
  skipped,
  bootstrapFailed,
  deferredBootstrapFailed,
}

class StartupSessionOrchestrator {
  const StartupSessionOrchestrator({
    required this.hubSessionCoordinator,
    required this.ports,
  });

  final HubSessionCoordinator hubSessionCoordinator;
  final StartupSessionPorts ports;

  Future<StartupSessionFlowResult> run({
    Future<DeferredBootPhaseOutcome> Function()? runDeferredBootstrapBeforeConnect,
    String defaultServerUrl = 'https://api.example.com',
  }) async {
    final deferredBootstrap = runDeferredBootstrapBeforeConnect;
    if (deferredBootstrap != null) {
      try {
        final outcome = await deferredBootstrap();
        if (outcome.shouldSkipHubAutoConnect) {
          AppLogger.warning(
            'Skipping Hub auto-connect after critical deferred bootstrap failure',
          );
          return StartupSessionFlowResult.deferredBootstrapFailed;
        }
      } on Object catch (error, stackTrace) {
        AppLogger.error(
          'Deferred bootstrap failed before Hub auto-connect',
          error,
          stackTrace,
        );
        return StartupSessionFlowResult.deferredBootstrapFailed;
      }
    }

    final attemptResult = await _attemptStartupLoginAndConnect(defaultServerUrl);
    return switch (attemptResult) {
      _StartupAttemptOutcome.completed => StartupSessionFlowResult.completed,
      _StartupAttemptOutcome.skipped => StartupSessionFlowResult.skipped,
      _StartupAttemptOutcome.bootstrapFailed => StartupSessionFlowResult.bootstrapFailed,
    };
  }

  Future<_StartupAttemptOutcome> _attemptStartupLoginAndConnect(String defaultServerUrl) async {
    final configSource = ports.config;
    final connectionGateway = ports.connection;
    final authSink = ports.auth;

    if (configSource.isLoading) {
      return _StartupAttemptOutcome.skipped;
    }
    if (connectionGateway.isConnected ||
        connectionGateway.status == ConnectionStatus.connecting ||
        connectionGateway.status == ConnectionStatus.negotiating ||
        connectionGateway.status == ConnectionStatus.reconnecting) {
      return _StartupAttemptOutcome.completed;
    }

    final config = configSource.currentConfig;
    if (config == null) {
      return _StartupAttemptOutcome.skipped;
    }

    final startupContext = _buildStartupContext(config, defaultServerUrl);
    if (startupContext == null) {
      return _StartupAttemptOutcome.skipped;
    }

    final bootstrapResult = await hubSessionCoordinator.bootstrapAutoSession(
      configId: startupContext.configId,
      serverUrl: startupContext.serverUrl,
      agentId: startupContext.agentId,
    );

    var shouldStop = false;
    var bootstrapFailedTerminally = false;
    AuthToken? startupToken;
    bootstrapResult.fold(
      (session) {
        startupToken = session.token;
        authSink.restoreToken(
          session.token,
          configId: startupContext.configId,
          silent: true,
        );
      },
      (failure) {
        if (failure is domain_errors.Failure && failure.isTransient) {
          connectionGateway.startPersistentHubRecovery(
            configId: startupContext.configId,
            serverUrl: startupContext.serverUrl,
            agentId: startupContext.agentId,
          );
        } else {
          if (failure is domain_errors.Failure) {
            failure.log(
              stackTrace: StackTrace.current,
              operation: 'startup_session_bootstrap',
            );
          }
          authSink.setRecoveryError(failure.toDisplayMessage());
          bootstrapFailedTerminally = true;
        }
        shouldStop = true;
      },
    );
    if (shouldStop || startupToken == null) {
      return bootstrapFailedTerminally ? _StartupAttemptOutcome.bootstrapFailed : _StartupAttemptOutcome.skipped;
    }

    final connectResult = await connectionGateway.connect(
      startupContext.serverUrl,
      startupContext.agentId,
      configId: startupContext.configId,
      authToken: startupToken!.token,
      recoverOnFailure: true,
    );
    return connectResult.isSuccess() ||
            connectionGateway.status == ConnectionStatus.reconnecting ||
            connectionGateway.isReconnecting
        ? _StartupAttemptOutcome.completed
        : _StartupAttemptOutcome.skipped;
  }

  _StartupCredentials? _buildStartupContext(Config config, String defaultServerUrl) {
    final serverUrl = normalizeServerUrl(config.serverUrl);
    final agentId = config.agentId.trim();

    if (serverUrl.isEmpty || serverUrl.toLowerCase() == defaultServerUrl || agentId.isEmpty) {
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

    return _StartupCredentials(
      configId: config.id,
      serverUrl: serverUrl,
      agentId: agentId,
    );
  }
}

enum _StartupAttemptOutcome {
  completed,
  skipped,
  bootstrapFailed,
}

class _StartupCredentials {
  const _StartupCredentials({
    required this.configId,
    required this.serverUrl,
    required this.agentId,
  });

  final String configId;
  final String serverUrl;
  final String agentId;
}
