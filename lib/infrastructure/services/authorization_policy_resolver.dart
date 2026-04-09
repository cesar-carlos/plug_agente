import 'dart:convert';
import 'dart:developer' as developer;

import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_authorization_cache_metrics.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
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
    IClientTokenPolicyCache? policyCache,
    IAuthorizationCacheMetrics? cacheMetrics,
  }) : _jwksVerifier = jwksVerifier,
       _localDataSource = localDataSource,
       _revokedTokenStore = revokedTokenStore,
       _tokenAuditStore = tokenAuditStore,
       _policyCache = policyCache,
       _cacheMetrics = cacheMetrics;

  final FeatureFlags _featureFlags;
  final JwtJwksVerifier? _jwksVerifier;
  final ClientTokenLocalDataSource? _localDataSource;
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
          'reason': 'token_revoked',
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

    if (_localDataSource != null) {
      final localResult = await _resolvePolicyFromLocalStore(rawToken);
      if (localResult.isSuccess()) {
        final policy = localResult.getOrNull();
        if (policy != null) {
          policyCache?.put(credentialHash, policy);
        }
        return localResult;
      }
      final localFailure = localResult.exceptionOrNull()! as domain.Failure;
      final shouldFallbackToJwks =
          localFailure.context['reason'] == 'token_not_found' &&
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

    final decodeResult = await _resolvePolicyDecodeOnly(token);
    if (decodeResult.isError()) {
      final failure = decodeResult.exceptionOrNull();
      if (failure is domain.Failure) {
        _addToRevokedStoreIfNeeded(rawToken, failure);
        await _recordAuthorizationDeniedAudit(failure);
      }
    } else {
      final policy = decodeResult.getOrNull();
      if (policy != null) {
        policyCache?.put(credentialHash, policy);
      }
    }
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
        tokenId: summary.id.isEmpty ? null : summary.id,
        issuedAt: summary.createdAt,
        tokenUpdatedAt: summary.updatedAt,
      ),
    );
  }

  Future<Result<ClientTokenPolicy>> _resolvePolicyDecodeOnly(
    String token,
  ) async {
    final rawToken = normalizeClientCredentialToken(token);
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
    final base = ClientTokenPolicy.fromJson(policyJson);
    final jwtTokenId = payload['jti'] as String?;
    final jwtIssuedAt = _jwtSecondsToUtc(payload['iat']);
    final merged = ClientTokenPolicy(
      clientId: base.clientId,
      agentId: base.agentId,
      payload: base.payload,
      allTables: base.allTables,
      allViews: base.allViews,
      allPermissions: base.allPermissions,
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
            'reason': 'invalid_policy',
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
            'reason': 'token_revoked',
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
            'reason': failure.context['reason'] ?? 'authorization_denied',
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
