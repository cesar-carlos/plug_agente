import 'package:result_dart/result_dart.dart';

import '../../domain/entities/auth_token.dart';
import '../../domain/errors/failures.dart' as domain;
import '../../domain/value_objects/auth_credentials.dart';
import '../services/auth_service.dart';

class LoginUser {
  final AuthService _service;

  LoginUser(this._service);

  Future<Result<AuthToken>> call(String serverUrl, AuthCredentials credentials) async {
    if (serverUrl.isEmpty) {
      return Failure(domain.ValidationFailure('Server URL cannot be empty'));
    }

    if (!credentials.isValid) {
      return Failure(domain.ValidationFailure('Username and password are required'));
    }

    return await _service.login(serverUrl, credentials);
  }
}
