import 'package:plug_agente/application/use_cases/load_agent_config.dart';
import 'package:plug_agente/application/use_cases/login_user.dart';
import 'package:plug_agente/application/use_cases/refresh_auth_token.dart';
import 'package:plug_agente/application/use_cases/save_auth_token.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:result_dart/result_dart.dart';

class HubRecoveryAuthCoordinator {
  HubRecoveryAuthCoordinator(
    this._loadAgentConfig,
    this._loginUser,
    this._refreshAuthToken,
    this._saveAuthToken,
    this._configRepository,
  );

  final LoadAgentConfig _loadAgentConfig;
  final LoginUser _loginUser;
  final RefreshAuthToken _refreshAuthToken;
  final SaveAuthToken _saveAuthToken;
  final IAgentConfigRepository _configRepository;

  Future<AuthToken?> loadPersistedTokenPair() async {
    final configResult = await _loadAgentConfig(null);
    return configResult.fold(
      (config) {
        final authToken = config.authToken?.trim();
        final refreshToken = config.refreshToken?.trim();
        if (authToken == null || authToken.isEmpty || refreshToken == null || refreshToken.isEmpty) {
          return null;
        }
        return AuthToken(
          token: authToken,
          refreshToken: refreshToken,
        );
      },
      (_) => null,
    );
  }

  Future<Result<AuthToken>> refreshSession(
    String serverUrl, {
    AuthToken? currentToken,
  }) async {
    final token = currentToken ?? await loadPersistedTokenPair();
    final refreshToken = token?.refreshToken.trim();
    if (refreshToken == null || refreshToken.isEmpty) {
      return Failure(
        domain_errors.ConfigurationFailure(
          'No refresh token available',
        ),
      );
    }

    final refreshResult = await _refreshAuthToken(serverUrl, refreshToken);
    return refreshResult.fold(
      (token) async => _persistRecoveredToken(token),
      Failure.new,
    );
  }

  Future<Result<AuthToken>> loginWithStoredCredentials(
    String serverUrl,
    String agentId,
  ) async {
    final configResult = await _loadAgentConfig(null);
    return configResult.fold(
      (config) async {
        final username = config.authUsername?.trim();
        final password = config.authPassword?.trim();
        if (username == null || username.isEmpty || password == null || password.isEmpty) {
          return Failure(
            domain_errors.ConfigurationFailure(
              'Saved username/password not found',
            ),
          );
        }

        final loginResult = await _loginUser(
          serverUrl,
          AuthCredentials(
            username: username,
            password: password,
            agentId: agentId,
          ),
        );
        return loginResult.fold(
          (token) async => _persistRecoveredToken(token),
          Failure.new,
        );
      },
      Failure.new,
    );
  }

  Future<Result<void>> clearStoredSession() async {
    final configResult = await _configRepository.getCurrentConfig();
    return configResult.fold(
      (config) => _configRepository
          .save(
            config.copyWith(
              authToken: null,
              refreshToken: null,
            ),
          )
          .fold(
            (_) => const Success(unit),
            Failure.new,
          ),
      Failure.new,
    );
  }

  Future<Result<AuthToken>> _persistRecoveredToken(AuthToken token) async {
    final saveResult = await _saveAuthToken(token);
    return saveResult.fold(
      (_) => Success(token),
      Failure.new,
    );
  }
}
