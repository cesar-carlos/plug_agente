import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

abstract final class ClientTokenLifetimeValidator {
  static Result<ClientTokenPolicy> validate(ClientTokenPolicy policy, {required DateTime now}) {
    if (!policy.isCredentialExpiredAt(now)) return Success(policy);
    return Failure(
      domain.ConfigurationFailure.withContext(
        message: 'Token has expired',
        context: {
          'authentication': true,
          'reason': AuthorizationContextConstants.tokenExpiredReason,
          'client_id': policy.clientId,
          'token_id': ?policy.tokenId,
          'user_message': 'Token expirado. Gere um novo token para continuar.',
        },
      ),
    );
  }
}
