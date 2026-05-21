import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/use_cases/login_user.dart';
import 'package:plug_agente/application/use_cases/refresh_auth_token.dart';
import 'package:plug_agente/application/use_cases/save_auth_token.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/repositories/i_hub_session_store.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:result_dart/result_dart.dart';

class HubSessionCoordinator {
  HubSessionCoordinator(
    this._activeConfigResolver,
    this._loginUser,
    this._refreshAuthToken,
    this._saveAuthToken,
    this._hubSessionStore,
  );

  final ActiveConfigResolver _activeConfigResolver;
  final LoginUser _loginUser;
  final RefreshAuthToken _refreshAuthToken;
  final SaveAuthToken _saveAuthToken;
  final IHubSessionStore _hubSessionStore;

  Future<AuthToken?> loadPersistedTokenPair(String? configId) async {
    final resolvedConfigIdResult = await _resolveConfigId(configId);
    if (resolvedConfigIdResult.isError()) {
      return null;
    }

    final sessionResult = await _hubSessionStore.readSession(
      resolvedConfigIdResult.getOrThrow(),
    );
    return sessionResult.fold(
      (session) => session.token,
      (_) => null,
    );
  }

  Future<Result<AuthToken>> login({
    required String configId,
    required String serverUrl,
    required AuthCredentials credentials,
  }) async {
    final loginResult = await _loginUser(serverUrl, credentials);
    return loginResult.fold(
      (token) async => _persistToken(configId: configId, token: token),
      Failure.new,
    );
  }

  Future<Result<AuthToken>> refreshSession(
    String serverUrl, {
    String? configId,
    AuthToken? currentToken,
  }) async {
    final resolvedConfigIdResult = await _resolveConfigId(configId);
    if (resolvedConfigIdResult.isError()) {
      return Failure(resolvedConfigIdResult.exceptionOrNull()!);
    }
    final resolvedConfigId = resolvedConfigIdResult.getOrThrow();
    final resolvedServerUrl = serverUrl.trim();
    if (resolvedServerUrl.isEmpty) {
      return Failure(
        domain_errors.ConfigurationFailure('No server URL available'),
      );
    }

    final token =
        currentToken ?? await loadPersistedTokenPair(resolvedConfigId);
    final refreshToken = token?.refreshToken.trim();
    if (refreshToken == null || refreshToken.isEmpty) {
      return Failure(
        domain_errors.ConfigurationFailure(
          'No refresh token available',
        ),
      );
    }

    final refreshResult = await _refreshAuthToken(
      resolvedServerUrl,
      refreshToken,
    );
    return refreshResult.fold(
      (refreshedToken) async => _persistToken(
        configId: resolvedConfigId,
        token: refreshedToken,
      ),
      Failure.new,
    );
  }

  Future<Result<AuthToken>> loginWithStoredCredentials(
    String serverUrl,
    String agentId, {
    String? configId,
  }) async {
    final resolvedConfigIdResult = await _resolveConfigId(configId);
    if (resolvedConfigIdResult.isError()) {
      return Failure(resolvedConfigIdResult.exceptionOrNull()!);
    }
    final resolvedConfigId = resolvedConfigIdResult.getOrThrow();
    final resolvedServerUrl = serverUrl.trim();
    final resolvedAgentId = agentId.trim();
    if (resolvedServerUrl.isEmpty) {
      return Failure(
        domain_errors.ConfigurationFailure('No server URL available'),
      );
    }
    if (resolvedAgentId.isEmpty) {
      return Failure(
        domain_errors.ConfigurationFailure('No agent ID available'),
      );
    }

    final credentialsResult = await _hubSessionStore.readStoredCredentials(
      resolvedConfigId,
    );
    return credentialsResult.fold(
      (credentialsState) async {
        final credentials = credentialsState.credentials;
        if (credentials == null) {
          return Failure(
            domain_errors.ConfigurationFailure(
              'Saved username/password not found',
            ),
          );
        }

        return login(
          configId: resolvedConfigId,
          serverUrl: resolvedServerUrl,
          credentials: AuthCredentials(
            username: credentials.username,
            password: credentials.password,
            agentId: resolvedAgentId,
          ),
        );
      },
      Failure.new,
    );
  }

  Future<Result<HubBootstrapSession>> bootstrapAutoSession({
    required String configId,
    required String serverUrl,
    required String agentId,
  }) async {
    final persistedToken = await loadPersistedTokenPair(configId);
    if (persistedToken != null) {
      return Success(
        HubBootstrapSession(
          token: persistedToken,
          source: HubBootstrapSource.persistedToken,
        ),
      );
    }

    final loginResult = await loginWithStoredCredentials(
      serverUrl,
      agentId,
      configId: configId,
    );
    return loginResult.fold(
      (token) => Success(
        HubBootstrapSession(
          token: token,
          source: HubBootstrapSource.storedCredentials,
        ),
      ),
      Failure.new,
    );
  }

  Future<Result<void>> clearStoredSession(String configId) async {
    final clearResult = await _hubSessionStore.clearSession(configId);
    return clearResult.fold(
      (_) => const Success(unit),
      Failure.new,
    );
  }

  Future<Result<AuthToken>> _persistToken({
    required String configId,
    required AuthToken token,
  }) async {
    final sessionResult = await _hubSessionStore.writeSessionTokens(
      configId,
      token,
    );
    if (sessionResult.isError()) {
      return Failure(sessionResult.exceptionOrNull()!);
    }

    final legacySaveResult = await _saveAuthToken(token);
    return legacySaveResult.fold(
      (_) => Success(token),
      Failure.new,
    );
  }

  String? _normalizeConfigId(String? configId) {
    final normalized = configId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Future<Result<String>> _resolveConfigId(String? configId) async {
    final normalized = _normalizeConfigId(configId);
    if (normalized != null) {
      return Success(normalized);
    }

    final configResult = await _activeConfigResolver.resolveActiveOrFallback(
      metadataOnly: true,
    );
    return configResult.fold(
      (config) => Success(config.id),
      Failure.new,
    );
  }
}

enum HubBootstrapSource {
  persistedToken,
  storedCredentials,
}

class HubBootstrapSession {
  const HubBootstrapSession({
    required this.token,
    required this.source,
  });

  final AuthToken token;
  final HubBootstrapSource source;
}
