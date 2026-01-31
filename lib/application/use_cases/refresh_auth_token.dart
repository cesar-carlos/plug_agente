import 'package:plug_agente/application/services/auth_service.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class RefreshAuthToken {
  RefreshAuthToken(this._service);
  final AuthService _service;

  Future<Result<AuthToken>> call(String serverUrl, String refreshToken) async {
    if (serverUrl.isEmpty) {
      return Failure(domain.ValidationFailure('Server URL cannot be empty'));
    }

    if (refreshToken.isEmpty) {
      return Failure(domain.ValidationFailure('Refresh token is required'));
    }

    return _service.refreshToken(serverUrl, refreshToken);
  }
}
