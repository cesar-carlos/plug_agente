import 'dart:convert';

import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:result_dart/result_dart.dart';

class AuthorizationPolicyResolver implements IAuthorizationPolicyResolver {
  @override
  Future<Result<ClientTokenPolicy>> resolvePolicy(String token) async {
    final rawToken = _normalizeToken(token);
    if (rawToken.isEmpty) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Missing client token',
          context: {
            'authentication': true,
          },
        ),
      );
    }

    final segments = rawToken.split('.');
    if (segments.length < 2) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Invalid token format',
          context: {
            'authentication': true,
            'reason': 'invalid_token_signature',
          },
        ),
      );
    }

    try {
      final payloadSegment = segments[1];
      final normalized = base64Url.normalize(payloadSegment);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(decoded) as Map<String, dynamic>;

      final policyJson = payload['policy'] as Map<String, dynamic>? ?? payload;
      final policy = ClientTokenPolicy.fromJson(policyJson);
      if (policy.clientId.trim().isEmpty) {
        return Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Invalid policy payload: client_id is required',
            context: {
              'authentication': true,
              'reason': 'invalid_policy',
            },
          ),
        );
      }

      if (payload['revoked'] == true || policy.isRevoked) {
        return Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Token revoked',
            context: {
              'authorization': true,
              'reason': 'token_revoked',
              'client_id': policy.clientId,
            },
          ),
        );
      }

      return Success(policy);
    } on FormatException catch (error) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Invalid token payload encoding',
          cause: error,
          context: {
            'authentication': true,
            'reason': 'invalid_token_signature',
          },
        ),
      );
    } on Exception catch (error) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Failed to parse token policy',
          cause: error,
          context: {
            'authentication': true,
            'reason': 'invalid_policy',
          },
        ),
      );
    }
  }

  String _normalizeToken(String token) {
    final value = token.trim();
    if (value.toLowerCase().startsWith('bearer ')) {
      return value.substring(7).trim();
    }
    return value;
  }
}
