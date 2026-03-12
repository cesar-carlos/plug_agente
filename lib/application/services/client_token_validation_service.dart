import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:result_dart/result_dart.dart';

class ClientTokenValidationService {
  ClientTokenValidationService(this._resolver);

  final IAuthorizationPolicyResolver _resolver;

  Future<Result<ClientTokenPolicy>> validate(String token) async {
    if (token.trim().isEmpty) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Client token is required',
          context: {
            'authentication': true,
          },
        ),
      );
    }

    return _resolver.resolvePolicy(token);
  }
}
