import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:result_dart/result_dart.dart';

class CreateClientToken {
  CreateClientToken(
    this._repository, {
    ITokenAuditStore? auditStore,
  }) : _auditStore = auditStore;

  final IClientTokenRepository _repository;
  final ITokenAuditStore? _auditStore;

  Future<Result<String>> call(ClientTokenCreateRequest request) async {
    if (request.clientId.trim().isEmpty) {
      return Failure(domain.ValidationFailure('client_id is required'));
    }

    if (!request.allPermissions && request.rules.isEmpty) {
      return Failure(
        domain.ValidationFailure(
          'At least one rule is required when all_permissions is false',
        ),
      );
    }

    final result = await _repository.createToken(request);
    result.fold(
      (token) {
        _auditStore?.record(
          TokenAuditEvent(
            eventType: TokenAuditEventType.create,
            timestamp: DateTime.now().toUtc(),
            clientId: request.clientId,
            metadata: {'agent_id': request.agentId},
          ),
        );
      },
      (_) {},
    );
    return result;
  }
}
