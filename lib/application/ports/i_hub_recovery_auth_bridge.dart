import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:result_dart/result_dart.dart';

/// Auth/session operations required by hub recovery without coupling to UI providers.
abstract interface class IHubRecoveryAuthBridge {
  AuthToken? currentTokenForConfig(String? configId);

  Future<Result<AuthToken>> refreshSession(
    String serverUrl, {
    String? configId,
    AuthToken? currentToken,
  });

  Future<Result<AuthToken>> loginWithStoredCredentials(
    String serverUrl,
    String agentId, {
    String? configId,
  });

  Future<void> clearStoredSession(String? configId);

  Future<void> logout({String? configId});

  void restoreToken(AuthToken token, {String? configId});

  void setRecoveryError(String message);
}
