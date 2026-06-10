import 'dart:developer' as developer;

import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_authorization_cache_metrics.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_revoked_token_store.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';
import 'package:result_dart/result_dart.dart';

class AuthorizationPolicyResolver implements IAuthorizationPolicyResolver {
  AuthorizationPolicyResolver(
    this._featureFlags, {
    JwtJwksVerifier? jwksVerifier,
    IClientTokenRepository? clientTokenRepository,
    IRevokedTokenStore? revokedTokenStore,
    ITokenAuditStore? tokenAuditStore,
    IClientTokenPolicyCache? policyCache,
    IAuthorizationCacheMetrics? cacheMetrics,
  }) : _jwksVerifier = jwksVerifier,
       _clientTokenRepository = clientTokenRepository,
       _revokedTokenStore = revokedTokenStore,
       _tokenAuditStore = tokenAuditStore,
       _policyCache = policyCache,
       _cacheMetrics = cacheMetrics;

  final FeatureFlags _featureFlags;
  final JwtJwksVerifier? _jwksVerifier;
  final IClientTokenRepository? _clientTokenRepository;
  final IRevokedTokenStore? _revokedTokenStore;
  final ITokenAuditStore? _tokenAuditStore;
  final IClientTokenPolicyCache? _policyCache;
  final IAuthorizationCacheMetrics? _cacheMetrics;

  @override
  Future<Result<ClientTokenPolicy>> resolvePolicy(String token) async {
    final rawToken = normalizeClientCredentialToken(token);
    if (rawToken.isEmpty) {
      final failure = domain.ConfigurationFailure.withContext(
        message: 'Missing client token',
        context: {'authentication': true},
      );
      await _recordAuthorizationDeniedAudit(failure);
      return Failure(failure);
    }

    if (_featureFlags.enableSocketRevokedTokenInSession &&
        _revokedTokenStore != null &&
        _revokedTokenStore.isRevoked(rawToken)) {
      final failure = domain.ConfigurationFailure.withContext(
        message: 'Token revoked',
        context: {
          'authorization': true,
          'reason': AuthorizationContextConstants.tokenRevokedReason,
        },
      );
      await _recordAuthorizationDeniedAudit(failure);
      return Failure(failure);
    }

    final policyCache = _policyCache;
    final credentialHash = hashClientCredentialToken(token);
    if (policyCache != null) {
      final cachedPolicy = policyCache.get(credentialHash);
      if (cachedPolicy != null) {
        _cacheMetrics?.recordPolicyCacheLookup(hit: true);
        return Success(cachedPolicy);
      }
      _cacheMetrics?.recordPolicyCacheLookup(hit: false);
    }

    final clientTokenRepository = _clientTokenRepository;
    if (clientTokenRepository != null) {
      final localResult = await _resolvePolicyFromLocalStore(
        clientTokenRepository,
        rawToken,
      );
      if (localResult.isSuccess()) {
        final policy = localResult.getOrNull();
        if (policy != null) {
          policyCache?.put(credentialHash, policy);
        }
        return localResult;
      }
      final localFailure = localResult.exceptionOrNull()! as domain.Failure;
      final shouldFallbackToJwks =
          localFailure.context['reason'] == AuthorizationContextConstants.tokenNotFoundReason &&
          _featureFlags.enableSocketJwksValidation &&
          _jwksVerifier != null;
      if (!shouldFallbackToJwks) {
        _addToRevokedStoreIfNeeded(rawToken, localFailure);
        await _recordAuthorizationDeniedAudit(localFailure);
        return Failure(localFailure);
      }
    }

    if (_featureFlags.enableSocketJwksValidation && _jwksVerifier != null) {
      final verifyResult = await _jwksVerifier.verify(rawToken);
      final jwksResolved = verifyResult.fold<Result<ClientTokenPolicy>>(
        (payload) {
          final policyResult = _extractPolicyFromPayload(payload);
          return policyResult;
        },
        Failure.new,
      );
      if (jwksResolved.isError()) {
        final failure = jwksResolved.exceptionOrNull();
        if (failure is domain.Failure) {
          _addToRevokedStoreIfNeeded(rawToken, failure);
          await _recordAuthorizationDeniedAudit(failure);
        }
      } else {
        final policy = jwksResolved.getOrNull();
        if (policy != null) {
          policyCache?.put(credentialHash, policy);
        }
      }
      return jwksResolved;
    }

    final failure = _unsignedTokenAuthenticationFailure();
    _addToRevokedStoreIfNeeded(rawToken, failure);
    await _recordAuthorizationDeniedAudit(failure);
    return Failure(failure);
  }

  Future<Result<ClientTokenPolicy>> _resolvePolicyFromLocalStore(
    IClientTokenRepository repository,
    String rawToken,
  ) async {
    final tokenHash = hashClientCredentialToken(rawToken);
    final summaryResult = await repository.getTokenByHash(tokenHash);
    if (summaryResult.isError()) {
      final error = summaryResult.exceptionOrNull();
      if (error is domain.Failure) {
        return _mapLocalStoreFailure(error);
      }
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Failed to resolve token policy from local store',
          cause: error,
          context: {
            'authentication': true,
            'reason': AuthorizationContextConstants.unauthorizedReason,
          },
        ),
      );
    }

    return _policyFromSummary(summaryResult.getOrThrow(), rawToken);
  }

  Result<ClientTokenPolicy> _policyFromSummary(
    ClientTokenSummary summary,
    String rawToken,
  ) {
    if (summary.isRevoked) {
      final failure = domain.ConfigurationFailure.withContext(
        message: 'Token revoked',
        context: {
          'authorization': true,
          'reason': AuthorizationContextConstants.tokenRevokedReason,
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
        globalPermissions: summary.globalPermissions,
        rules: summary.rules,
        agentId: summary.agentId,
        payload: summary.payload,
        isRevoked: summary.isRevoked,
        tokenId: summary.id.isEmpty ? null : summary.id,
        issuedAt: summary.createdAt,
        tokenUpdatedAt: summary.updatedAt,
      ),
    );
  }

  Result<ClientTokenPolicy> _mapLocalStoreFailure(domain.Failure failure) {
    if (failure is domain.NotFoundFailure) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Token not found in local store',
          context: {
            'authorization': true,
            'reason': AuthorizationContextConstants.tokenNotFoundReason,
          },
        ),
      );
    }

    if (failure is domain.ServerFailure) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Failed to resolve token policy from local store',
          cause: failure.cause,
          context: {
            'authentication': true,
            'reason': AuthorizationContextConstants.unauthorizedReason,
            'operation': failure.context['operation'],
          },
        ),
      );
    }

    return Failure(failure);
  }

  domain.ConfigurationFailure _unsignedTokenAuthenticationFailure() {
    return domain.ConfigurationFailure.withContext(
      message: 'Token signature verification is required',
      context: {
        'authentication': true,
        'reason': AuthorizationContextConstants.invalidTokenSignatureReason,
      },
    );
  }

  Result<ClientTokenPolicy> _extractPolicyFromPayload(
    Map<String, dynamic> payload,
  ) {
    final policyJson = payload['policy'] as Map<String, dynamic>? ?? payload;
    final base = ClientTokenPolicy.fromJson(policyJson);
    final jwtTokenId = payload['jti'] as String?;
    final jwtIssuedAt = _jwtSecondsToUtc(payload['iat']);
    final merged = ClientTokenPolicy(
      clientId: base.clientId,
      agentId: base.agentId,
      payload: base.payload,
      allTables: base.allTables,
      allViews: base.allViews,
      globalPermissions: base.globalPermissions,
      isRevoked: base.isRevoked,
      rules: base.rules,
      tokenId: base.tokenId ?? jwtTokenId,
      issuedAt: base.issuedAt ?? jwtIssuedAt,
      tokenUpdatedAt: base.tokenUpdatedAt,
    );
    if (merged.clientId.trim().isEmpty) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Invalid policy payload: client_id is required',
          context: {
            'authentication': true,
            'reason': AuthorizationContextConstants.invalidPolicyReason,
          },
        ),
      );
    }

    if (payload['revoked'] == true || merged.isRevoked) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Token revoked',
          context: {
            'authorization': true,
            'reason': AuthorizationContextConstants.tokenRevokedReason,
            'client_id': merged.clientId,
          },
        ),
      );
    }

    return Success(merged);
  }

  DateTime? _jwtSecondsToUtc(Object? raw) {
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw * 1000, isUtc: true);
    }
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt() * 1000, isUtc: true);
    }
    return null;
  }

  void _addToRevokedStoreIfNeeded(String token, domain.Failure failure) {
    if (!_featureFlags.enableSocketRevokedTokenInSession || _revokedTokenStore == null) {
      return;
    }
    final reason = failure.context['reason'] as String?;
    if (reason == AuthorizationContextConstants.tokenRevokedReason) {
      if (token.isNotEmpty) {
        _revokedTokenStore.add(token);
      }
      final clientId = failure.context['client_id'] as String?;
      _tokenAuditStore?.record(
        TokenAuditEvent(
          eventType: TokenAuditEventType.revokedInSession,
          timestamp: DateTime.now().toUtc(),
          clientId: clientId,
          metadata: {'reason': AuthorizationContextConstants.tokenRevokedReason},
        ),
      );
    }
  }

  Future<void> _recordAuthorizationDeniedAudit(domain.Failure failure) async {
    final auditStore = _tokenAuditStore;
    if (auditStore == null) {
      return;
    }
    try {
      await auditStore.record(
        TokenAuditEvent(
          eventType: TokenAuditEventType.authorizationDenied,
          timestamp: DateTime.now().toUtc(),
          clientId: failure.context['client_id'] as String?,
          tokenId: failure.context['token_id'] as String?,
          metadata: {
            'reason': failure.context['reason'] ?? AuthorizationContextConstants.authorizationDeniedReason,
            'message': failure.message,
          },
        ),
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Authorization denied audit failed (best effort only)',
        name: 'authorization_policy_resolver',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
