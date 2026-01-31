import 'package:plug_agente/application/services/auth_service.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:result_dart/result_dart.dart';

class LoginUser {
  LoginUser(this._service);
  final AuthService _service;

  Future<Result<AuthToken>> call(
    String serverUrl,
    AuthCredentials credentials,
  ) async {
    if (serverUrl.isEmpty) {
      return Failure(domain.ValidationFailure('Server URL cannot be empty'));
    }

    if (!credentials.isValid) {
      return Failure(
        domain.ValidationFailure('Username and password are required'),
      );
    }

    return _service.login(serverUrl, credentials);
  }
}
