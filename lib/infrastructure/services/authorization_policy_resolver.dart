import 'dart:developer' as developer;

import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/core/utils/jwt_numeric_date.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/client_token_runtime_restrictions.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_authorization_cache_metrics.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_revoked_token_store.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/services/client_token_lifetime_validator.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';
import 'package:result_dart/result_dart.dart';

const String _tokenRevokedUserMessage = 'Token revogado. Gere um novo token para continuar.';
const String _localStoreReadUserMessage =
    'Nao foi possivel ler a politica do token no armazenamento local. Tente novamente.';

class AuthorizationPolicyResolver implements IAuthorizationPolicyResolver {
  AuthorizationPolicyResolver(
    this._featureFlags, {
    JwtJwksVerifier? jwksVerifier,
    IClientTokenRepository? clientTokenRepository,
    IRevokedTokenStore? revokedTokenStore,
    ITokenAuditStore? tokenAuditStore,
    IClientTokenPolicyCache? policyCache,
    IAuthorizationCacheMetrics? cacheMetrics,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _jwksVerifier = jwksVerifier,
       _clientTokenRepository = clientTokenRepository,
       _revokedTokenStore = revokedTokenStore,
       _tokenAuditStore = tokenAuditStore,
       _policyCache = policyCache,
       _cacheMetrics = cacheMetrics;

  final FeatureFlags _featureFlags;
  final DateTime Function() _now;
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
        context: {
          'authentication': true,
          'reason': AuthorizationContextConstants.unauthorizedReason,
          'user_message': 'Informe o token de cliente na requisicao para executar esta operacao.',
        },
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
          'user_message': _tokenRevokedUserMessage,
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
        return _validateResolvedLifetime(Success(cachedPolicy), credentialHash);
      }
      _cacheMetrics?.recordPolicyCacheLookup(hit: false);
    }

    final clientTokenRepository = _clientTokenRepository;
    if (policyCache != null) {
      final joined = policyCache.hasPendingResolution(credentialHash);
      if (joined) {
        _cacheMetrics?.recordPolicyResolutionJoined();
      } else {
        _cacheMetrics?.recordPolicyResolutionStarted();
      }
      final resolution = await policyCache.resolveSingleFlight(
        credentialHash,
        () => _resolveUncachedPolicy(rawToken, clientTokenRepository),
      );
      if (!resolution.isCurrent) {
        // A revoke/rotation/delete won the race. Re-check revocation and load
        // the current policy instead of letting an old lookup authorize.
        return resolvePolicy(token);
      }
      return _validateResolvedLifetime(resolution.result, credentialHash);
    }

    return _validateResolvedLifetime(await _resolveUncachedPolicy(rawToken, clientTokenRepository), credentialHash);
  }

  Future<Result<ClientTokenPolicy>> _validateResolvedLifetime(
    Result<ClientTokenPolicy> resolved,
    String credentialHash,
  ) async {
    if (resolved.isError()) return resolved;
    final result = ClientTokenLifetimeValidator.validate(resolved.getOrThrow(), now: _now());
    if (result.isError()) {
      _policyCache?.invalidate(credentialHash);
      await _recordAuthorizationDeniedAudit(result.exceptionOrNull()! as domain.Failure);
    }
    return result;
  }

  Future<Result<ClientTokenPolicy>> _resolveUncachedPolicy(
    String rawToken,
    IClientTokenRepository? clientTokenRepository,
  ) async {
    if (clientTokenRepository != null) {
      final localResult = await _resolvePolicyFromLocalStore(
        clientTokenRepository,
        rawToken,
      );
      if (localResult.isSuccess()) {
        return localResult;
      }
      final localFailure = localResult.exceptionOrNull()! as domain.Failure;
      final shouldFallbackToJwks =
          localFailure.context['reason'] == AuthorizationContextConstants.tokenNotFoundReason &&
          _featureFlags.enableSocketJwksValidation &&
          _jwksVerifier != null;
      if (!shouldFallbackToJwks) {
        await _addToRevokedStoreIfNeeded(rawToken, localFailure);
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
          await _addToRevokedStoreIfNeeded(rawToken, failure);
          await _recordAuthorizationDeniedAudit(failure);
        }
      }
      return jwksResolved;
    }

    final failure = _unsignedTokenAuthenticationFailure();
    await _addToRevokedStoreIfNeeded(rawToken, failure);
    await _recordAuthorizationDeniedAudit(failure);
    return Failure(failure);
  }

  Future<Result<ClientTokenPolicy>> _resolvePolicyFromLocalStore(
    IClientTokenRepository repository,
    String rawToken,
  ) async {
    final tokenHash = hashClientCredentialToken(rawToken);
    final summaryResult = await repository.getTokenPolicySummaryByHash(tokenHash);
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
            'user_message': _localStoreReadUserMessage,
          },
        ),
      );
    }

    return _policyFromSummary(summaryResult.getOrThrow());
  }

  Result<ClientTokenPolicy> _policyFromSummary(
    ClientTokenSummary summary,
  ) {
    if (summary.hasInvalidPolicy) {
      return _invalidPolicyPayload(const FormatException('Invalid token policy'));
    }
    if (!ClientTokenRuntimeRestrictions.isValidPayload(summary.payload)) {
      return _invalidPolicyPayload(const FormatException('Invalid token runtime restrictions'));
    }
    if (summary.isRevoked) {
      final failure = domain.ConfigurationFailure.withContext(
        message: 'Token revoked',
        context: {
          'authorization': true,
          'reason': AuthorizationContextConstants.tokenRevokedReason,
          'client_id': summary.clientId,
          'token_id': summary.id,
          'user_message': _tokenRevokedUserMessage,
        },
      );
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
            'user_message':
                'Token de cliente nao encontrado. Confirme se o valor enviado e o token atual; alteracoes de permissao rotacionam o token.',
          },
        ),
      );
    }

    if (failure is domain.ServerFailure || failure is domain.DatabaseFailure) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Failed to resolve token policy from local store',
          cause: failure.cause,
          context: {
            ...failure.context,
            'authentication': true,
            'reason': AuthorizationContextConstants.unauthorizedReason,
            'retryable': failure.isTransient || failure.context['retryable'] == true,
            'user_message': _localStoreReadUserMessage,
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
        'user_message': 'A verificacao da assinatura do token e obrigatoria. Confira a configuracao JWKS do agente.',
      },
    );
  }

  Result<ClientTokenPolicy> _extractPolicyFromPayload(
    Map<String, dynamic> payload,
  ) {
    try {
      return _parsePolicyFromPayload(payload);
    } on FormatException catch (error) {
      return _invalidPolicyPayload(error);
    }
  }

  Result<ClientTokenPolicy> _invalidPolicyPayload(Object cause) {
    return Failure(
      domain.ConfigurationFailure.withContext(
        message: 'Invalid token policy payload',
        cause: cause,
        context: {
          'authentication': true,
          'reason': AuthorizationContextConstants.invalidPolicyReason,
          'user_message': 'Politica do token invalida. Gere outro token com permissoes validas.',
        },
      ),
    );
  }

  Result<ClientTokenPolicy> _parsePolicyFromPayload(Map<String, dynamic> payload) {
    final rawPolicy = payload['policy'];
    if (rawPolicy != null && rawPolicy is! Map<String, dynamic>) {
      throw const FormatException('Token policy must be an object');
    }
    final policyJson = rawPolicy as Map<String, dynamic>? ?? payload;
    final rawRules = policyJson['rules'];
    if (rawRules != null && (rawRules is! List || rawRules.any((rule) => rule is! Map<String, dynamic>))) {
      throw const FormatException('Token policy rules must contain objects');
    }
    final rawPermissions = policyJson['global_permissions'];
    if (rawPermissions != null && rawPermissions is! Map<String, dynamic>) {
      throw const FormatException('Token global permissions must be an object');
    }
    final rawRevoked = payload['revoked'];
    if (rawRevoked != null && rawRevoked is! bool) {
      throw const FormatException('Token revoked claim must be a boolean');
    }
    _validateOptionalFields<String>(policyJson, const ['client_id', 'agent_id', 'token_id']);
    _validateOptionalFields<bool>(policyJson, const ['all_tables', 'all_views', 'all_permissions', 'is_revoked']);
    _validateOptionalFields<Map<String, dynamic>>(policyJson, const ['payload']);
    _validateOptionalFields<String>(payload, const ['jti']);
    const permissionFields = ['read', 'update', 'delete', 'ddl'];
    if (rawPermissions is Map<String, dynamic>) {
      _validateOptionalFields<bool>(rawPermissions, permissionFields);
    }
    if (rawRules is List) {
      for (final rule in rawRules.cast<Map<String, dynamic>>()) {
        _validateOptionalFields<String>(rule, const ['effect', 'resource_type', 'resource']);
        _validateOptionalFields<bool>(rule, permissionFields);
      }
    }
    final base = ClientTokenPolicy.fromJson(policyJson);
    if (!ClientTokenRuntimeRestrictions.isValidPayload(base.payload)) {
      throw const FormatException('Invalid token runtime restrictions');
    }
    final jwtTokenId = payload['jti'] as String?;
    final jwtIssuedAt = parseJwtNumericDate(payload['iat'], claim: 'iat');
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
      credentialExpiresAt: parseJwtNumericDate(payload['exp'], claim: 'exp'),
    );
    if (merged.clientId.trim().isEmpty) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Invalid policy payload: client_id is required',
          context: {
            'authentication': true,
            'reason': AuthorizationContextConstants.invalidPolicyReason,
            'user_message': 'Politica do token invalida: client_id e obrigatorio.',
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
            'user_message': _tokenRevokedUserMessage,
          },
        ),
      );
    }

    return Success(merged);
  }

  void _validateOptionalFields<T>(Map<String, dynamic> source, List<String> fields) {
    for (final field in fields) {
      final value = source[field];
      if (value != null && value is! T) {
        throw FormatException('Invalid token policy field: $field');
      }
    }
  }

  Future<void> _addToRevokedStoreIfNeeded(String token, domain.Failure failure) async {
    if (!_featureFlags.enableSocketRevokedTokenInSession || _revokedTokenStore == null) {
      return;
    }
    final reason = failure.context['reason'] as String?;
    if (reason != AuthorizationContextConstants.tokenRevokedReason || token.isEmpty) {
      return;
    }
    _revokedTokenStore.add(token);
    await _recordAuditEvent(
      TokenAuditEvent(
        eventType: TokenAuditEventType.revokedInSession,
        timestamp: DateTime.now().toUtc(),
        clientId: failure.context['client_id'] as String?,
        tokenId: failure.context['token_id'] as String?,
        metadata: {'reason': AuthorizationContextConstants.tokenRevokedReason},
      ),
    );
  }

  Future<void> _recordAuthorizationDeniedAudit(domain.Failure failure) {
    return _recordAuditEvent(
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
  }

  Future<void> _recordAuditEvent(TokenAuditEvent event) async {
    final auditStore = _tokenAuditStore;
    if (auditStore == null) {
      return;
    }
    try {
      await auditStore.record(event);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Authorization audit failed (best effort only)',
        name: 'authorization_policy_resolver',
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
    }
  }
}
