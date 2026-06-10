import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:result_dart/result_dart.dart';

/// Renews hub access tokens for authenticated HTTP calls.
abstract interface class IHubAccessTokenRenewer {
  Future<Result<AuthToken>> renew({
    required String serverUrl,
    required String accessToken,
    String? configId,
  });
}
