import 'dart:developer' as developer;

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
    if (result.isSuccess()) {
      await _recordCreateAuditEvent(request);
    }
    return result;
  }

  Future<void> _recordCreateAuditEvent(ClientTokenCreateRequest request) async {
    if (_auditStore == null) {
      return;
    }
    try {
      await _auditStore.record(
        TokenAuditEvent(
          eventType: TokenAuditEventType.create,
          timestamp: DateTime.now().toUtc(),
          clientId: request.clientId,
          metadata: {'agent_id': request.agentId},
        ),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to record client token create audit event',
        name: 'create_client_token_use_case',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
