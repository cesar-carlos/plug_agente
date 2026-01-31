import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
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
    final configResult = await _configRepository.getCurrentConfig();

    return configResult.fold(
      (config) async {
        final updatedConfig = config.copyWith(
          authToken: token.token,
          refreshToken: token.refreshToken,
          updatedAt: DateTime.now(),
        );

        // Try/catch apenas na operação de I/O com repositório
        try {
          final saveResult = await _configRepository.save(updatedConfig);
          return saveResult.fold(
            (_) => const Success(unit),
            Failure.new,
          );
        } on Exception catch (e, stackTrace) {
          AppLogger.error(
            'Exception saving config to repository',
            e,
            stackTrace,
          );
          return Failure(
            domain_errors.DatabaseFailure(
              'Failed to save config: $e',
            ),
          );
        }
      },
      (failure) =>
          Failure(domain_errors.NotFoundFailure('No configuration found')),
    );
  }
}
