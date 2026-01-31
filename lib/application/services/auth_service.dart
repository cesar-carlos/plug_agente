import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_auth_client.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:result_dart/result_dart.dart';

class AuthService {
  AuthService(this._authClient, this._configRepository);
  final IAuthClient _authClient;
  final IAgentConfigRepository _configRepository;

  Future<Result<AuthToken>> login(
    String serverUrl,
    AuthCredentials credentials,
  ) async {
    return _authClient.login(serverUrl, credentials);
  }

  Future<Result<AuthToken>> refreshToken(
    String serverUrl,
    String refreshToken,
  ) async {
    return _authClient.refreshToken(serverUrl, refreshToken);
  }

  Future<Result<void>> saveAuthToken(AuthToken token) async {
    try {
      final configResult = await _configRepository.getCurrentConfig();

      return await configResult.fold(
        (config) async {
          final updatedConfig = config.copyWith(
            authToken: token.token,
            refreshToken: token.refreshToken,
            updatedAt: DateTime.now(),
          );
          final saveResult = await _configRepository.save(updatedConfig);
          return saveResult.fold(
            (_) => const Success<Object, Exception>(Object()),
            (
              failure,
            ) {
              final failureMessage = failure is domain.Failure
                  ? failure.message
                  : failure.toString();
              return Failure(
                domain.DatabaseFailure(
                  'Failed to save config: $failureMessage',
                ),
              );
            },
          );
        },
        (failure) async {
          return Failure(domain.NotFoundFailure('No configuration found'));
        },
      );
    } on Exception catch (e) {
      return Failure(domain.DatabaseFailure('Failed to save auth token: $e'));
    }
  }
}
