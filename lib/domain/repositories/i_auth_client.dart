import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:result_dart/result_dart.dart';

abstract class IAuthClient {
  Future<Result<AuthToken>> login(
    String serverUrl,
    AuthCredentials credentials,
  );
  Future<Result<AuthToken>> refreshToken(String serverUrl, String refreshToken);
}
