import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/repositories/i_auth_client.dart';
import 'package:plug_agente/domain/repositories/i_hub_session_store.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:result_dart/result_dart.dart';

class AuthService {
  AuthService(this._authClient, this._hubSessionStore);
  final IAuthClient _authClient;
  final IHubSessionStore _hubSessionStore;

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

  Future<Result<void>> saveAuthToken(
    String configId,
    AuthToken token,
  ) async {
    try {
      final saveResult = await _hubSessionStore.writeSessionTokens(
        configId,
        token,
      );
      return saveResult.fold(
        (_) => const Success(unit),
        Failure.new,
      );
    } on Exception catch (e, stackTrace) {
      AppLogger.error(
        'Exception saving hub session token',
        e,
        stackTrace,
      );
      return Failure(
        domain_errors.DatabaseFailure.withContext(
          message: 'Failed to persist hub session token',
          cause: e,
          context: {
            'operation': 'saveAuthToken',
            'configId': configId,
          },
        ),
      );
    }
  }
}
