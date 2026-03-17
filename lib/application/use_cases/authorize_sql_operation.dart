import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:result_dart/result_dart.dart';

class AuthorizeSqlOperation {
  AuthorizeSqlOperation(
    this._classifier,
    this._tokenValidationService, {
    IAuthorizationDecisionCache? decisionCache,
    Duration decisionTtl = const Duration(seconds: 30),
  }) : _decisionCache = decisionCache,
       _decisionTtl = decisionTtl;

  final SqlOperationClassifier _classifier;
  final ClientTokenValidationService _tokenValidationService;
  final IAuthorizationDecisionCache? _decisionCache;
  final Duration _decisionTtl;

  Future<Result<void>> call({
    required String token,
    required String sql,
    String? requestId,
    String? method,
  }) async {
    final classificationResult = _classifier.classify(sql);
    return classificationResult.fold(
      (classification) async {
        final tokenHash = _hashToken(token);
        final decisionKeys = classification.resources
            .map(
              (resource) => _decisionCacheKey(
                tokenHash: tokenHash,
                operation: classification.operation.name,
                resource: resource.normalizedName,
              ),
            )
            .toList(growable: false);

        final cachedDecision = _resolveFromDecisionCache(
          keys: decisionKeys,
          operation: classification.operation.name,
          resources: classification.resources.map((r) => r.normalizedName),
        );
        if (cachedDecision != null) {
          return cachedDecision;
        }

        final policyResult = await _tokenValidationService.validate(token);
        return policyResult.fold(
          (policy) async {
            for (var i = 0; i < classification.resources.length; i++) {
              final resource = classification.resources[i];
              final allowed = policy.isAllowed(
                operation: classification.operation,
                resource: resource,
              );
              if (!allowed) {
                final reason = policy.isRevoked
                    ? 'token_revoked'
                    : 'missing_permission';
                _cacheDecision(
                  key: decisionKeys[i],
                  allowed: false,
                  clientId: policy.clientId,
                  reason: reason,
                  requestId: requestId,
                  method: method,
                );
                final userMessage = policy.isRevoked
                    ? 'Token revogado. Gere um novo token para continuar.'
                    : 'Seu cliente nao possui permissao para '
                          '${_operationLabel(classification.operation)} '
                          'neste recurso.';
                return Failure(
                  domain.ConfigurationFailure.withContext(
                    message:
                        'Authorization denied for '
                        '${classification.operation.name} '
                        'on ${resource.normalizedName}',
                    context: {
                      'authorization': true,
                      'reason': reason,
                      'client_id': policy.clientId,
                      'operation': classification.operation.name,
                      'resource': resource.normalizedName,
                      'user_message': userMessage,
                    },
                  ),
                );
              }
              _cacheDecision(
                key: decisionKeys[i],
                allowed: true,
                clientId: policy.clientId,
                requestId: requestId,
                method: method,
              );
            }
            return const Success(unit);
          },
          (failure) {
            final error = failure as domain.Failure;
            for (final key in decisionKeys) {
              _cacheDecision(
                key: key,
                allowed: false,
                clientId: error.context['client_id'] as String?,
                reason: error.context['reason'] as String?,
                requestId: requestId,
                method: method,
              );
            }
            return Failure(error);
          },
        );
      },
      (_) async {
        return Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Authorization denied: unsupported SQL classification',
            context: {
              'authorization': true,
              'reason': 'invalid_policy',
              'user_message':
                  'Comando SQL nao suportado para autorizacao. '
                  'Revise a consulta enviada.',
            },
          ),
        );
      },
    );
  }

  Result<void>? _resolveFromDecisionCache({
    required List<String> keys,
    required String operation,
    required Iterable<String> resources,
  }) {
    final cache = _decisionCache;
    if (cache == null || keys.isEmpty) {
      return null;
    }

    final entries = <AuthorizationDecisionCacheEntry>[];
    for (final key in keys) {
      final entry = cache.get(key);
      if (entry == null) {
        return null;
      }
      entries.add(entry);
    }

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.allowed) {
        continue;
      }
      final resource = resources.elementAt(i);
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Authorization denied for $operation on $resource',
          context: {
            'authorization': true,
            'reason': entry.reason ?? 'missing_permission',
            if (entry.clientId != null) 'client_id': entry.clientId,
            'operation': operation,
            'resource': resource,
          },
        ),
      );
    }

    return const Success(unit);
  }

  void _cacheDecision({
    required String key,
    required bool allowed,
    String? clientId,
    String? reason,
    String? requestId,
    String? method,
  }) {
    final cache = _decisionCache;
    if (cache == null) {
      return;
    }
    cache.put(
      key,
      AuthorizationDecisionCacheEntry(
        allowed: allowed,
        clientId: clientId,
        reason: reason,
        requestId: requestId,
        method: method,
        expiresAt: DateTime.now().add(_decisionTtl),
      ),
    );
  }

  String _decisionCacheKey({
    required String tokenHash,
    required String operation,
    required String resource,
  }) {
    return '$tokenHash|$operation|$resource';
  }

  String _hashToken(String token) {
    final normalized = token.trim();
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  String _operationLabel(SqlOperation operation) {
    return switch (operation) {
      SqlOperation.read => 'consultar',
      SqlOperation.update => 'alterar',
      SqlOperation.delete => 'excluir',
    };
  }
}
