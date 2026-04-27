import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_authorization_cache_metrics.dart';
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:result_dart/result_dart.dart';

const int _kMaxResourceNamesInTechnicalMessage = 20;

class AuthorizeSqlOperation {
  AuthorizeSqlOperation(
    this._classifier,
    this._tokenValidationService, {
    IAuthorizationDecisionCache? decisionCache,
    IAuthorizationCacheMetrics? cacheMetrics,
    Duration decisionTtl = const Duration(seconds: 30),
  }) : _decisionCache = decisionCache,
       _cacheMetrics = cacheMetrics,
       _decisionTtl = decisionTtl;

  final SqlOperationClassifier _classifier;
  final ClientTokenValidationService _tokenValidationService;
  final IAuthorizationDecisionCache? _decisionCache;
  final IAuthorizationCacheMetrics? _cacheMetrics;
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
        final tokenHash = hashClientCredentialToken(token);
        final resources = classification.resources;
        final decisionKeys = resources
            .map(
              (resource) => _decisionCacheKey(
                tokenHash: tokenHash,
                operation: classification.operation.name,
                resource: resource.normalizedName,
              ),
            )
            .toList(growable: false);

        final cache = _decisionCache;
        final missIndices = <int>[];
        final deniedNames = <String>{};
        final reasonByDeniedName = <String, String>{};
        String? clientIdFromCache;

        for (var i = 0; i < resources.length; i++) {
          final name = resources[i].normalizedName;
          if (cache == null) {
            missIndices.add(i);
            continue;
          }
          final entry = cache.get(decisionKeys[i]);
          _cacheMetrics?.recordDecisionCacheLookup(hit: entry != null);
          if (entry == null) {
            missIndices.add(i);
            continue;
          }
          if (entry.allowed) {
            continue;
          }
          deniedNames.add(name);
          if (clientIdFromCache == null && entry.clientId != null && entry.clientId!.isNotEmpty) {
            clientIdFromCache = entry.clientId;
          }
          _recordReasonForName(
            reasonByDeniedName: reasonByDeniedName,
            name: name,
            reason: entry.reason ?? 'missing_permission',
          );
        }

        if (missIndices.isEmpty) {
          if (deniedNames.isEmpty) {
            return const Success(unit);
          }
          return Failure(
            _buildAuthorizationFailure(
              classification: classification,
              policy: null,
              deniedNames: deniedNames,
              reasonByDeniedName: reasonByDeniedName,
              clientIdFromCache: clientIdFromCache,
            ),
          );
        }

        final policyResult = await _tokenValidationService.validate(token);
        return policyResult.fold(
          (policy) {
            for (final i in missIndices) {
              final resource = resources[i];
              final allowed = policy.isAllowed(
                operation: classification.operation,
                resource: resource,
              );
              if (allowed) {
                _cacheDecision(
                  key: decisionKeys[i],
                  allowed: true,
                  clientId: policy.clientId,
                  requestId: requestId,
                  method: method,
                );
              } else {
                final name = resource.normalizedName;
                final reason = policy.isRevoked ? 'token_revoked' : 'missing_permission';
                _cacheDecision(
                  key: decisionKeys[i],
                  allowed: false,
                  clientId: policy.clientId,
                  reason: reason,
                  requestId: requestId,
                  method: method,
                );
                deniedNames.add(name);
                _recordReasonForName(
                  reasonByDeniedName: reasonByDeniedName,
                  name: name,
                  reason: reason,
                );
              }
            }
            if (deniedNames.isEmpty) {
              return const Success(unit);
            }
            return Failure(
              _buildAuthorizationFailure(
                classification: classification,
                policy: policy,
                deniedNames: deniedNames,
                reasonByDeniedName: reasonByDeniedName,
                clientIdFromCache: clientIdFromCache,
              ),
            );
          },
          (failure) {
            final error = failure is domain.Failure
                ? failure
                : domain.ConfigurationFailure.withContext(
                    message: failure.toString(),
                    context: const {'authorization': true, 'reason': 'unexpected_failure_type'},
                  );
            for (final i in missIndices) {
              _cacheDecision(
                key: decisionKeys[i],
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

  void _recordReasonForName({
    required Map<String, String> reasonByDeniedName,
    required String name,
    required String reason,
  }) {
    final existing = reasonByDeniedName[name];
    if (existing == 'token_revoked' || reason == 'token_revoked') {
      reasonByDeniedName[name] = 'token_revoked';
      return;
    }
    if (existing == null) {
      reasonByDeniedName[name] = reason;
    }
  }

  domain.ConfigurationFailure _buildAuthorizationFailure({
    required SqlOperationClassification classification,
    required ClientTokenPolicy? policy,
    required Set<String> deniedNames,
    required Map<String, String> reasonByDeniedName,
    String? clientIdFromCache,
  }) {
    final sorted = deniedNames.toList()..sort();
    final topReason = _resolveTopLevelReason(
      reasonByDeniedName: reasonByDeniedName,
      policy: policy,
    );
    final clientId = _resolveClientId(
      policy: policy,
      clientIdFromCache: clientIdFromCache,
    );
    final opName = classification.operation.name;
    final resourceList = _formatNameListForMessage(sorted);
    final userMessage = topReason == 'token_revoked'
        ? 'Token revogado. Gere um novo token para continuar. '
              'Recursos na consulta: $resourceList.'
        : 'Acesso negado para ${_operationLabel(classification.operation)} '
              'nos recursos: $resourceList.';

    return domain.ConfigurationFailure.withContext(
      message: _formatTechnicalMessage(
        operation: opName,
        resourceNames: sorted,
      ),
      context: {
        'authorization': true,
        'reason': topReason,
        'client_id': ?clientId,
        'operation': opName,
        'resource': sorted.first,
        'denied_resources': sorted,
        'user_message': userMessage,
      },
    );
  }

  String _resolveTopLevelReason({
    required Map<String, String> reasonByDeniedName,
    required ClientTokenPolicy? policy,
  }) {
    if (policy != null && policy.isRevoked) {
      return 'token_revoked';
    }
    for (final r in reasonByDeniedName.values) {
      if (r == 'token_revoked') {
        return 'token_revoked';
      }
    }
    return 'missing_permission';
  }

  String? _resolveClientId({
    required ClientTokenPolicy? policy,
    String? clientIdFromCache,
  }) {
    if (policy != null && policy.clientId.isNotEmpty) {
      return policy.clientId;
    }
    if (clientIdFromCache != null && clientIdFromCache.isNotEmpty) {
      return clientIdFromCache;
    }
    return null;
  }

  String _formatNameListForMessage(List<String> sorted) {
    return sorted.map((e) => e).join(', ');
  }

  String _formatTechnicalMessage({
    required String operation,
    required List<String> resourceNames,
  }) {
    if (resourceNames.isEmpty) {
      return 'Authorization denied for $operation';
    }
    if (resourceNames.length <= _kMaxResourceNamesInTechnicalMessage) {
      return 'Authorization denied for $operation on ${resourceNames.join(', ')}';
    }
    final head = resourceNames.take(_kMaxResourceNamesInTechnicalMessage).join(', ');
    final rest = resourceNames.length - _kMaxResourceNamesInTechnicalMessage;
    return 'Authorization denied for $operation on $head (+$rest more)';
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

  String _operationLabel(SqlOperation operation) {
    return switch (operation) {
      SqlOperation.read => 'consultar',
      SqlOperation.update => 'alterar',
      SqlOperation.delete => 'excluir',
    };
  }
}
