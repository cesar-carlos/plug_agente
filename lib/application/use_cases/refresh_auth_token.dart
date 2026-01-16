import 'package:result_dart/result_dart.dart';

import '../../domain/entities/auth_token.dart';
import '../../domain/errors/failures.dart' as domain;
import '../services/auth_service.dart';

class RefreshAuthToken {
  final AuthService _service;

  RefreshAuthToken(this._service);

  Future<Result<AuthToken>> call(String serverUrl, String refreshToken) async {
    if (serverUrl.isEmpty) {
      return Failure(domain.ValidationFailure('Server URL cannot be empty'));
    }

    if (refreshToken.isEmpty) {
      return Failure(domain.ValidationFailure('Refresh token is required'));
    }

    return await _service.refreshToken(serverUrl, refreshToken);
  }
}
