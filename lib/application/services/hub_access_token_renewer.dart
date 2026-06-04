import 'package:plug_agente/application/ports/i_hub_access_token_renewer.dart';
import 'package:plug_agente/application/ports/i_hub_recovery_auth_bridge.dart';
import 'package:plug_agente/application/services/hub_access_token_refresh_gate.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:result_dart/result_dart.dart';

/// Renews hub access tokens for authenticated HTTP calls and proactive refresh.
///
/// The auth bridge is bound at runtime from presentation (same lifecycle as
/// [IHubRecoveryAuthBridge] for socket recovery).
class HubAccessTokenRenewer implements IHubAccessTokenRenewer {
  HubAccessTokenRenewer(
    this._sessionCoordinator,
    this._refreshGate,
  );

  final HubSessionCoordinator _sessionCoordinator;
  final HubAccessTokenRefreshGate _refreshGate;
  IHubRecoveryAuthBridge? _authBridge;
  void Function()? _onAccessTokenRestored;

  void bindAuthBridge(IHubRecoveryAuthBridge bridge) {
    _authBridge = bridge;
  }

  void clearAuthBridge() {
    _authBridge = null;
  }

  void setOnAccessTokenRestored(void Function()? callback) {
    _onAccessTokenRestored = callback;
  }

  @override
  Future<Result<AuthToken>> renew({
    required String serverUrl,
    required String accessToken,
    String? configId,
  }) async {
    final bridge = _authBridge;
    if (bridge == null) {
      return Failure(
        domain_errors.ConfigurationFailure(
          'Hub auth bridge is not available',
        ),
      );
    }

    final normalizedAccess = accessToken.trim();
    final currentTokenResult = await _resolveCurrentToken(
      bridge: bridge,
      configId: configId,
      accessToken: normalizedAccess,
    );
    if (currentTokenResult.isError()) {
      return Failure(currentTokenResult.exceptionOrNull()!);
    }

    var refreshResult = await _refreshGate.runExclusive<Result<AuthToken>>(
      () => bridge.refreshSession(
        serverUrl,
        configId: configId,
        currentToken: currentTokenResult.getOrThrow(),
      ),
      logContext: 'hub_http_token_renew',
    );

    if (refreshResult == null) {
      await _refreshGate.waitForCooldownOrInFlight();
      refreshResult = await _refreshGate.runExclusive<Result<AuthToken>>(
        () => bridge.refreshSession(
          serverUrl,
          configId: configId,
          currentToken: currentTokenResult.getOrThrow(),
        ),
        logContext: 'hub_http_token_renew',
      );
    }

    if (refreshResult == null) {
      return Failure(
        domain_errors.ConfigurationFailure(
          'Hub token refresh skipped (cooldown)',
        ),
      );
    }

    return refreshResult.fold(
      (token) {
        bridge.restoreToken(token, configId: configId, silent: true);
        _onAccessTokenRestored?.call();
        return Success(token);
      },
      Failure.new,
    );
  }

  Future<Result<AuthToken>> _resolveCurrentToken({
    required IHubRecoveryAuthBridge bridge,
    required String accessToken,
    String? configId,
  }) async {
    final fromBridge = bridge.currentTokenForConfig(configId);
    if (fromBridge != null && fromBridge.refreshToken.trim().isNotEmpty) {
      final access = fromBridge.token.trim().isNotEmpty ? fromBridge.token.trim() : accessToken;
      return Success(
        AuthToken(token: access, refreshToken: fromBridge.refreshToken.trim()),
      );
    }

    final persisted = await _sessionCoordinator.loadPersistedTokenPair(configId);
    if (persisted != null && persisted.refreshToken.trim().isNotEmpty) {
      final access = persisted.token.trim().isNotEmpty ? persisted.token.trim() : accessToken;
      return Success(
        AuthToken(token: access, refreshToken: persisted.refreshToken.trim()),
      );
    }

    return Failure(
      domain_errors.ConfigurationFailure(
        'No refresh token available',
      ),
    );
  }
}
