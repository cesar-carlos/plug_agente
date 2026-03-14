import 'dart:convert';

import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/repositories/i_revoked_token_store.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';
import 'package:result_dart/result_dart.dart';

class AuthorizationPolicyResolver implements IAuthorizationPolicyResolver {
  AuthorizationPolicyResolver(
    this._featureFlags, {
    JwtJwksVerifier? jwksVerifier,
    ClientTokenLocalDataSource? localDataSource,
    IRevokedTokenStore? revokedTokenStore,
    ITokenAuditStore? tokenAuditStore,
  }) : _jwksVerifier = jwksVerifier,
       _localDataSource = localDataSource,
       _revokedTokenStore = revokedTokenStore,
       _tokenAuditStore = tokenAuditStore;

  final FeatureFlags _featureFlags;
  final JwtJwksVerifier? _jwksVerifier;
  final ClientTokenLocalDataSource? _localDataSource;
  final IRevokedTokenStore? _revokedTokenStore;
  final ITokenAuditStore? _tokenAuditStore;

  @override
  Future<Result<ClientTokenPolicy>> resolvePolicy(String token) async {
    final rawToken = _normalizeToken(token);
    if (rawToken.isEmpty) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Missing client token',
          context: {'authentication': true},
        ),
      );
    }

    if (_featureFlags.enableSocketRevokedTokenInSession &&
        _revokedTokenStore != null &&
        _revokedTokenStore.isRevoked(rawToken)) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Token revoked',
          context: {
            'authorization': true,
            'reason': 'token_revoked',
          },
        ),
      );
    }

    if (_localDataSource != null) {
      final localResult = await _resolvePolicyFromLocalStore(rawToken);
      if (localResult.isSuccess()) {
        return localResult;
      }
      return Failure(localResult.exceptionOrNull()! as domain.Failure);
    }

    if (_featureFlags.enableSocketJwksValidation && _jwksVerifier != null) {
      final verifyResult = await _jwksVerifier.verify(rawToken);
      return verifyResult.fold(
        (payload) {
          final policyResult = _extractPolicyFromPayload(payload);
          policyResult.fold(
            (_) {},
            (f) {
              if (f is domain.Failure) {
                _addToRevokedStoreIfNeeded(rawToken, f);
              }
            },
          );
          return policyResult;
        },
        Failure.new,
      );
    }

    final decodeResult = await _resolvePolicyDecodeOnly(token);
    decodeResult.fold(
      (_) {},
      (f) {
        if (f is domain.Failure) {
          _addToRevokedStoreIfNeeded(rawToken, f);
        }
      },
    );
    return decodeResult;
  }

  Future<Result<ClientTokenPolicy>> _resolvePolicyFromLocalStore(
    String rawToken,
  ) async {
    final tokenHash = _localDataSource!.hashTokenForLookup(rawToken);
    final summary = await _localDataSource.getTokenByHash(tokenHash);
    if (summary == null) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Token not found in local store',
          context: {
            'authorization': true,
            'reason': 'token_not_found',
          },
        ),
      );
    }

    if (summary.isRevoked) {
      final failure = domain.ConfigurationFailure.withContext(
        message: 'Token revoked',
        context: {
          'authorization': true,
          'reason': 'token_revoked',
          'client_id': summary.clientId,
          'token_id': summary.id,
        },
      );
      _addToRevokedStoreIfNeeded(rawToken, failure);
      return Failure(failure);
    }

    return Success(
      ClientTokenPolicy(
        clientId: summary.clientId,
        allTables: summary.allTables,
        allViews: summary.allViews,
        allPermissions: summary.allPermissions,
        rules: summary.rules,
        agentId: summary.agentId,
        payload: summary.payload,
        isRevoked: summary.isRevoked,
      ),
    );
  }

  Future<Result<ClientTokenPolicy>> _resolvePolicyDecodeOnly(
    String token,
  ) async {
    final rawToken = _normalizeToken(token);
    if (rawToken.isEmpty) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Missing client token',
          context: {'authentication': true},
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
      return _extractPolicyFromPayload(payload);
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

  Result<ClientTokenPolicy> _extractPolicyFromPayload(
    Map<String, dynamic> payload,
  ) {
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
  }

  void _addToRevokedStoreIfNeeded(String token, domain.Failure failure) {
    if (!_featureFlags.enableSocketRevokedTokenInSession || _revokedTokenStore == null) {
      return;
    }
    final reason = failure.context['reason'] as String?;
    if (reason == 'token_revoked') {
      _revokedTokenStore.add(token);
      final clientId = failure.context['client_id'] as String?;
      _tokenAuditStore?.record(
        TokenAuditEvent(
          eventType: TokenAuditEventType.revokedInSession,
          timestamp: DateTime.now().toUtc(),
          clientId: clientId,
          metadata: {'reason': 'token_revoked'},
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
