import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:result_dart/result_dart.dart';

class AuthorizeSqlOperation {
  AuthorizeSqlOperation(
    this._classifier,
    this._tokenValidationService,
  );

  final SqlOperationClassifier _classifier;
  final ClientTokenValidationService _tokenValidationService;

  Future<Result<void>> call({
    required String token,
    required String sql,
  }) async {
    final classificationResult = _classifier.classify(sql);
    return classificationResult.fold(
      (classification) async {
        final policyResult = await _tokenValidationService.validate(token);
        return policyResult.fold(
          (policy) async {
            for (final resource in classification.resources) {
              final allowed = policy.isAllowed(
                operation: classification.operation,
                resource: resource,
              );
              if (!allowed) {
                final reason = policy.isRevoked
                    ? 'token_revoked'
                    : 'missing_permission';
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
            }
            return const Success(unit);
          },
          Failure.new,
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

  String _operationLabel(SqlOperation operation) {
    return switch (operation) {
      SqlOperation.read => 'consultar',
      SqlOperation.update => 'alterar',
      SqlOperation.delete => 'excluir',
    };
  }
}
