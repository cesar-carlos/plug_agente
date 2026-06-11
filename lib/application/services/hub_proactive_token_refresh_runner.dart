import 'package:plug_agente/application/services/hub_access_token_refresh_gate.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';

/// Executes proactive hub access-token refresh and optional transport reconnect.
final class HubProactiveTokenRefreshRunner {
  HubProactiveTokenRefreshRunner({
    required HubProactiveTokenRefreshRuntimeDependencies runtime,
  }) : _deps = runtime;

  final HubProactiveTokenRefreshRuntimeDependencies _deps;

  Future<void> run() async {
    if (_deps.isDisconnectRequested() || !_deps.isConnected()) {
      return;
    }

    final context = _deps.resolveConnectionContext();
    if (context == null) {
      return;
    }

    AppLogger.info('Proactive hub access token refresh due');
    final refreshResult = await _deps.tryRefreshToken(context);
    switch (refreshResult.kind) {
      case TokenRefreshResultKind.refreshed:
        AppLogger.info('Proactive hub access token refresh succeeded');
        final token = refreshResult.token;
        if (token != null && token.isNotEmpty) {
          await _reconnectTransportWithRefreshedToken(context, token);
        }
      case TokenRefreshResultKind.skippedByCooldown:
        AppLogger.debug('Proactive hub access token refresh skipped (cooldown)');
      case TokenRefreshResultKind.transientFailure:
        AppLogger.warning('Proactive hub access token refresh transient failure');
        _deps.kickHubTransportRecovery(trigger: 'proactive_refresh_transient');
      case TokenRefreshResultKind.terminalFailure:
        AppLogger.warning('Proactive hub access token refresh failed');
        if (!_deps.isDisconnectRequested()) {
          _deps.onTerminalRefreshFailure();
          _deps.kickHubTransportRecovery(trigger: 'proactive_refresh_terminal');
        }
    }

    if (!_deps.isDisconnectRequested() && _deps.isConnected()) {
      _deps.rescheduleProactiveRefresh();
    }
  }

  Future<String?> resolveReconnectTokenAfterRefresh(
    HubConnectionContext context,
    TokenRefreshResult refreshResult,
  ) async {
    switch (refreshResult.kind) {
      case TokenRefreshResultKind.refreshed:
        return refreshResult.token;
      case TokenRefreshResultKind.skippedByCooldown:
        await _deps.tokenRefreshGate.waitForCooldownOrInFlight();
        final retry = await _deps.tryRefreshToken(context);
        if (retry.kind == TokenRefreshResultKind.refreshed) {
          return retry.token;
        }
        if (_deps.isSessionAuthInvalid()) {
          return null;
        }
        return _deps.resolveAuthTokenForReconnect();
      case TokenRefreshResultKind.transientFailure:
        return _deps.resolveAuthTokenForReconnect();
      case TokenRefreshResultKind.terminalFailure:
        return null;
    }
  }

  Future<void> _reconnectTransportWithRefreshedToken(
    HubConnectionContext context,
    String token,
  ) async {
    if (_deps.isDisconnectRequested() || !_deps.isConnected()) {
      return;
    }
    try {
      await _deps.disconnectTransport();
      await _deps.attemptReconnect(
        context.serverUrl,
        context.agentId,
        authToken: token,
        recordErrorMessage: false,
      );
    } on Exception catch (error, stackTrace) {
      AppLogger.warning(
        'Proactive refresh reconnect failed: $error',
        error,
        stackTrace,
      );
      _deps.kickHubTransportRecovery(trigger: 'proactive_refresh_reconnect');
    }
  }
}

final class HubProactiveTokenRefreshRuntimeDependencies {
  HubProactiveTokenRefreshRuntimeDependencies({
    required this.tokenRefreshGate,
    required this.isDisconnectRequested,
    required this.isConnected,
    required this.isSessionAuthInvalid,
    required this.resolveConnectionContext,
    required this.resolveAuthTokenForReconnect,
    required this.tryRefreshToken,
    required this.disconnectTransport,
    required this.attemptReconnect,
    required this.kickHubTransportRecovery,
    required this.onTerminalRefreshFailure,
    required this.rescheduleProactiveRefresh,
  });

  final HubAccessTokenRefreshGate tokenRefreshGate;
  final bool Function() isDisconnectRequested;
  final bool Function() isConnected;
  final bool Function() isSessionAuthInvalid;
  final HubConnectionContext? Function() resolveConnectionContext;
  final String? Function() resolveAuthTokenForReconnect;
  final Future<TokenRefreshResult> Function(HubConnectionContext context) tryRefreshToken;
  final Future<void> Function() disconnectTransport;
  final Future<bool> Function(
    String serverUrl,
    String agentId, {
    String? authToken,
    bool recordErrorMessage,
  })
  attemptReconnect;
  final void Function({required String trigger}) kickHubTransportRecovery;
  final void Function() onTerminalRefreshFailure;
  final void Function() rescheduleProactiveRefresh;
}
