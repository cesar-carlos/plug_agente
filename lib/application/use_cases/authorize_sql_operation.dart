import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
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
    String? requestDatabase,
    String? requestId,
    String? method,
  }) async {
    final classificationResult = _classifier.classify(sql);
    return classificationResult.fold(
      (classification) async {
        final tokenHash = hashClientCredentialToken(token);
        final normalizedRequestDatabase = _normalizeDatabaseName(
          requestDatabase,
        );
        final resources = classification.resources;
        final decisionKeys = resources
            .map(
              (resource) => _decisionCacheKey(
                tokenHash: tokenHash,
                operation: classification.operation.name,
                resource: resource.normalizedName,
                requestDatabase: normalizedRequestDatabase,
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
            reason: entry.reason ?? AuthorizationContextConstants.missingPermissionReason,
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
            final databaseConstraintFailure = _validateDatabaseConstraint(
              policy: policy,
              requestDatabase: normalizedRequestDatabase,
              classification: classification,
            );
            if (databaseConstraintFailure != null) {
              final reason = databaseConstraintFailure.context['reason'] as String?;
              for (final i in missIndices) {
                _cacheDecision(
                  key: decisionKeys[i],
                  allowed: false,
                  clientId: policy.clientId,
                  reason: reason,
                  requestId: requestId,
                  method: method,
                );
              }
              return Failure(databaseConstraintFailure);
            }

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
                final reason = policy.isRevoked
                    ? AuthorizationContextConstants.tokenRevokedReason
                    : AuthorizationContextConstants.missingPermissionReason;
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
                    context: const {
                      'authorization': true,
                      'reason': AuthorizationContextConstants.unexpectedFailureTypeReason,
                    },
                  );
            if (!_isTransientTokenResolverFailure(error)) {
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
              'reason': AuthorizationContextConstants.invalidPolicyReason,
              'user_message': 'Comando SQL nao suportado para autorizacao. Revise a consulta enviada.',
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
    if (existing == AuthorizationContextConstants.tokenRevokedReason ||
        reason == AuthorizationContextConstants.tokenRevokedReason) {
      reasonByDeniedName[name] = AuthorizationContextConstants.tokenRevokedReason;
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
    final userMessage = switch (topReason) {
      AuthorizationContextConstants.tokenRevokedReason =>
        'Token revogado. Gere um novo token para continuar. Recursos na consulta: $resourceList.',
      AuthorizationContextConstants.databaseRequiredReason =>
        'Este token exige que a request informe o database configurado no payload antes de ${_operationLabel(classification.operation)}: $resourceList.',
      AuthorizationContextConstants.databaseMismatchReason =>
        'O database enviado na request nao corresponde ao database configurado no token para ${_operationLabel(classification.operation)}: $resourceList.',
      _ => 'Acesso negado para ${_operationLabel(classification.operation)} nos recursos: $resourceList.',
    };

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
      return AuthorizationContextConstants.tokenRevokedReason;
    }
    for (final reason in reasonByDeniedName.values) {
      if (reason == AuthorizationContextConstants.tokenRevokedReason) {
        return AuthorizationContextConstants.tokenRevokedReason;
      }
      if (reason == AuthorizationContextConstants.databaseRequiredReason ||
          reason == AuthorizationContextConstants.databaseMismatchReason) {
        return reason;
      }
    }
    return AuthorizationContextConstants.missingPermissionReason;
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
    return sorted.join(', ');
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
    required String? requestDatabase,
  }) {
    if (requestDatabase == null) {
      return '$tokenHash|$operation|$resource';
    }
    return '$tokenHash|$operation|db:$requestDatabase|$resource';
  }

  String _operationLabel(SqlOperation operation) {
    return switch (operation) {
      SqlOperation.read => 'consultar',
      SqlOperation.update => 'alterar',
      SqlOperation.delete => 'excluir',
      SqlOperation.ddl => 'executar DDL',
    };
  }

  domain.ConfigurationFailure? _validateDatabaseConstraint({
    required ClientTokenPolicy policy,
    required String? requestDatabase,
    required SqlOperationClassification classification,
  }) {
    final expectedDatabase = policy.payloadDatabaseConstraint;
    if (expectedDatabase == null) {
      return null;
    }

    if (requestDatabase == null) {
      return domain.ConfigurationFailure.withContext(
        message: 'Authorization denied: database is required and must match token payload.database',
        context: {
          'authorization': true,
          'reason': AuthorizationContextConstants.databaseRequiredReason,
          'client_id': policy.clientId,
          'operation': classification.operation.name,
          'resource': classification.resources.first.normalizedName,
          'denied_resources': classification.resources
              .map((resource) => resource.normalizedName)
              .toList(growable: false),
          'expected_database': expectedDatabase,
          'user_message': 'Este token exige que a request informe o database "$expectedDatabase".',
        },
      );
    }

    if (requestDatabase == expectedDatabase) {
      return null;
    }

    return domain.ConfigurationFailure.withContext(
      message:
          'Authorization denied: request database "$requestDatabase" does not match token payload.database "$expectedDatabase"',
      context: {
        'authorization': true,
        'reason': AuthorizationContextConstants.databaseMismatchReason,
        'client_id': policy.clientId,
        'operation': classification.operation.name,
        'resource': classification.resources.first.normalizedName,
        'denied_resources': classification.resources.map((resource) => resource.normalizedName).toList(growable: false),
        'expected_database': expectedDatabase,
        'request_database': requestDatabase,
        'user_message':
            'Este token esta restrito ao database "$expectedDatabase". Database recebido: "$requestDatabase".',
      },
    );
  }

  bool _isTransientTokenResolverFailure(domain.Failure failure) {
    if (failure is domain.NetworkFailure) {
      return true;
    }
    if (failure.context['authorization'] == true) {
      return false;
    }
    return failure.isTransient;
  }

  String? _normalizeDatabaseName(String? rawValue) {
    final normalized = rawValue?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
