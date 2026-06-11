import 'package:plug_agente/application/services/hub_proactive_token_refresh_runner.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';

/// Handles hub transport token-expiry callbacks and escalates through recovery.
final class HubTokenExpiryRecoveryCoordinator {
  HubTokenExpiryRecoveryCoordinator({
    required HubTokenExpiryRecoveryRuntimeDependencies runtime,
    required HubProactiveTokenRefreshRunner proactiveRefreshRunner,
  }) : _deps = runtime,
       _proactiveRefreshRunner = proactiveRefreshRunner;

  final HubTokenExpiryRecoveryRuntimeDependencies _deps;
  final HubProactiveTokenRefreshRunner _proactiveRefreshRunner;

  Future<void> handleTokenExpired() async {
    if (_deps.isDisconnectRequested()) {
      return;
    }

    if (_deps.isInternalReconnecting()) {
      final context = _deps.resolveConnectionContext();
      if (context != null) {
        AppLogger.warning(
          'Hub reported authentication failure during reconnect; refreshing token',
        );
        AppLogger.debug(
          'resilience: ${_deps.resilienceLogPrefix()}token_refresh event=during_reconnect_burst '
          'agent_id=${context.agentId}',
        );
        await _deps.tryRefreshToken(context);
      }
      return;
    }

    _deps.beginTokenExpiryRecovery();
    AppLogger.warning('Token expired, attempting refresh...');
    _deps.notifyStateChanged();

    try {
      _deps.resilienceCoordinator.beginResilienceRecovery();
      await _deps.disconnectTransport();
      _deps.reconfigureTransportCallbacks();

      final context = _deps.resolveConnectionContext();
      if (context == null) {
        _deps.resilienceCoordinator.clearResilienceRecovery();
        _deps.onMissingConnectionContextForTokenRefresh();
        AppLogger.error('Cannot refresh token without connection context');
      } else {
        final refreshResult = await _deps.tryRefreshToken(context);
        final reconnectToken = await _proactiveRefreshRunner.resolveReconnectTokenAfterRefresh(
          context,
          refreshResult,
        );
        if (reconnectToken == null) {
          _deps.resilienceCoordinator.clearResilienceRecovery();
          _deps.onTokenRefreshFailed();
          AppLogger.error('Token refresh failed during reconnect policy');
        } else {
          final connected = await _deps.attemptReconnect(
            context.serverUrl,
            context.agentId,
            authToken: reconnectToken,
          );
          if (connected) {
            AppLogger.info('Reconnected with refreshed token successfully');
          } else if (!_deps.isDisconnectRequested()) {
            AppLogger.warning(
              'Single reconnect with refreshed token failed; escalating to recovery burst',
            );
            final recovered = await _deps.recoverConnection(context);
            if (!recovered && !_deps.isDisconnectRequested()) {
              AppLogger.warning(
                'Recovery burst exhausted after token refresh; starting persistent retry',
              );
              _deps.startPersistentRetry();
            }
          }
        }
      }
    } on Exception catch (error, stackTrace) {
      _deps.resilienceCoordinator.clearResilienceRecovery();
      _deps.clearHubRecoveryUiHint();
      final failure = domain_errors.ConnectionFailure.withContext(
        message: 'Failed to refresh token',
        cause: error,
        context: {'operation': 'handleTokenExpired'},
      );
      _deps.onTokenRefreshException(failure.toDisplayMessage());
      AppLogger.error(
        'Token refresh failed: ${failure.toDisplayMessage()}',
        error,
        stackTrace,
      );
    } finally {
      _deps.endTokenExpiryRecovery();
      _deps.notifyStateChanged();
    }
  }
}

final class HubTokenExpiryRecoveryRuntimeDependencies {
  HubTokenExpiryRecoveryRuntimeDependencies({
    required this.resilienceCoordinator,
    required this.resilienceLogPrefix,
    required this.isDisconnectRequested,
    required this.isInternalReconnecting,
    required this.resolveConnectionContext,
    required this.tryRefreshToken,
    required this.disconnectTransport,
    required this.reconfigureTransportCallbacks,
    required this.attemptReconnect,
    required this.recoverConnection,
    required this.startPersistentRetry,
    required this.beginTokenExpiryRecovery,
    required this.endTokenExpiryRecovery,
    required this.onMissingConnectionContextForTokenRefresh,
    required this.onTokenRefreshFailed,
    required this.onTokenRefreshException,
    required this.clearHubRecoveryUiHint,
    required this.notifyStateChanged,
  });

  final HubResilienceCoordinator resilienceCoordinator;
  final String Function() resilienceLogPrefix;
  final bool Function() isDisconnectRequested;
  final bool Function() isInternalReconnecting;
  final HubConnectionContext? Function() resolveConnectionContext;
  final Future<TokenRefreshResult> Function(HubConnectionContext context) tryRefreshToken;
  final Future<void> Function() disconnectTransport;
  final void Function() reconfigureTransportCallbacks;
  final Future<bool> Function(
    String serverUrl,
    String agentId, {
    String? authToken,
    bool recordErrorMessage,
  })
  attemptReconnect;
  final Future<bool> Function(HubConnectionContext context) recoverConnection;
  final void Function() startPersistentRetry;
  final void Function() beginTokenExpiryRecovery;
  final void Function() endTokenExpiryRecovery;
  final void Function() onMissingConnectionContextForTokenRefresh;
  final void Function() onTokenRefreshFailed;
  final void Function(String message) onTokenRefreshException;
  final void Function() clearHubRecoveryUiHint;
  final void Function() notifyStateChanged;
}
