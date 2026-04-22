import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

/// Mirrors authorization decisions from RPC responses (allow/denied/auth-fail)
/// to the message tracer and triggers a single token refresh per session when
/// the hub indicates the credential is bad.
///
/// Encapsulates the rule "log + maybe refresh once" so the transport client
/// only has to feed it the (request, response, clientToken) triple.
class AuthorizationDecisionLogger {
  AuthorizationDecisionLogger({
    required FeatureFlags featureFlags,
    required void Function(String direction, String event, dynamic data) logMessage,
    required String Function() agentIdProvider,
    required void Function() onTokenRefreshRequested,
  }) : _featureFlags = featureFlags,
       _logMessage = logMessage,
       _agentIdProvider = agentIdProvider,
       _onTokenRefreshRequested = onTokenRefreshRequested;

  final FeatureFlags _featureFlags;
  final void Function(String direction, String event, dynamic data) _logMessage;
  final String Function() _agentIdProvider;
  final void Function() _onTokenRefreshRequested;

  bool _tokenRefreshRequested = false;

  /// Resets the once-per-session refresh latch. Call from the transport client
  /// when a fresh socket connection is established.
  void resetSessionState() {
    _tokenRefreshRequested = false;
  }

  /// Logs the authorization decision and, when applicable (auth failed or
  /// token revoked), triggers a single token refresh.
  void log({
    required RpcRequest request,
    required RpcResponse response,
    required String? clientToken,
  }) {
    if (!_featureFlags.enableClientTokenAuthorization) {
      return;
    }

    if (clientToken == null || clientToken.isEmpty) {
      return;
    }

    final isAuthRelevantMethod =
        request.method.startsWith('sql.') ||
        (request.method == 'client_token.getPolicy' && _featureFlags.enableClientTokenPolicyIntrospection);
    if (!isAuthRelevantMethod) {
      return;
    }

    final error = response.error;
    if (error == null) {
      _logMessage('AUTH', 'authorization.allowed', {
        'request_id': request.id,
        'method': request.method,
      });
      return;
    }

    final errorData = error.data;
    final reason = errorData is Map<String, dynamic> ? (errorData['reason'] as String?) : null;

    if (error.code == RpcErrorCode.authenticationFailed) {
      _logMessage('AUTH', 'authorization.authentication_failed', {
        'request_id': request.id,
        'method': request.method,
        ...?reason != null ? {'reason': reason} : null,
      });
      _requestTokenRefresh('authentication_failed');
      return;
    }

    if (error.code != RpcErrorCode.unauthorized) {
      return;
    }

    final payload = <String, dynamic>{
      'request_id': request.id,
      'method': request.method,
      'code': error.code,
      'reason': 'unauthorized',
    };

    if (errorData is Map<String, dynamic>) {
      payload.addAll({
        'reason': errorData['reason'] ?? payload['reason'],
        'client_id': errorData['client_id'],
        'operation': errorData['operation'],
        'resource': errorData['resource'],
        'denied_resources': errorData['denied_resources'],
      });
      payload.removeWhere((key, value) => value == null);
    }

    _logMessage('AUTH', 'authorization.denied', payload);

    if (payload['reason'] == 'token_revoked') {
      _requestTokenRefresh('token_revoked');
    }
  }

  void _requestTokenRefresh(String reason) {
    if (_tokenRefreshRequested) {
      return;
    }

    _tokenRefreshRequested = true;
    _logMessage('AUTH', 'authorization.token_refresh_requested', {
      'reason': reason,
      'agent_id': _agentIdProvider(),
    });
    _onTokenRefreshRequested();
  }
}
