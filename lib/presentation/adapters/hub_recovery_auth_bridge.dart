import 'package:plug_agente/application/ports/i_hub_recovery_auth_bridge.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:result_dart/result_dart.dart';

/// Presentation adapter for [IHubRecoveryAuthBridge] backed by auth/session collaborators.
class HubRecoveryAuthBridge implements IHubRecoveryAuthBridge {
  HubRecoveryAuthBridge({
    required HubSessionCoordinator sessionCoordinator,
    required AuthProvider authProvider,
  }) : _sessionCoordinator = sessionCoordinator,
       _authProvider = authProvider;

  final HubSessionCoordinator _sessionCoordinator;
  final AuthProvider _authProvider;

  @override
  AuthToken? currentTokenForConfig(String? configId) => _authProvider.currentTokenForConfig(configId);

  @override
  Future<Result<AuthToken>> refreshSession(
    String serverUrl, {
    String? configId,
    AuthToken? currentToken,
  }) {
    return _sessionCoordinator.refreshSession(
      serverUrl,
      configId: configId,
      currentToken: currentToken,
    );
  }

  @override
  Future<Result<AuthToken>> loginWithStoredCredentials(
    String serverUrl,
    String agentId, {
    String? configId,
  }) {
    return _sessionCoordinator.loginWithStoredCredentials(
      serverUrl,
      agentId,
      configId: configId,
    );
  }

  @override
  Future<void> clearStoredSession(String? configId) {
    final resolvedConfigId = configId?.trim();
    if (resolvedConfigId == null || resolvedConfigId.isEmpty) {
      return Future<void>.value();
    }
    return _sessionCoordinator.clearStoredSession(resolvedConfigId).then((_) {});
  }

  @override
  Future<void> logout({String? configId}) {
    return _authProvider.logout(configId: configId);
  }

  @override
  void restoreToken(AuthToken token, {String? configId}) {
    _authProvider.restoreToken(token, configId: configId);
  }

  @override
  void setRecoveryError(String message) {
    _authProvider.setRecoveryError(message);
  }
}
