import 'package:result_dart/result_dart.dart';

import '../entities/auth_token.dart';
import '../value_objects/auth_credentials.dart';

abstract class IAuthClient {
  Future<Result<AuthToken>> login(String serverUrl, AuthCredentials credentials);
  Future<Result<AuthToken>> refreshToken(String serverUrl, String refreshToken);
}
