import 'dart:developer' as developer;

import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:result_dart/result_dart.dart';

class UpdateClientToken {
  UpdateClientToken(
    this._repository, {
    ITokenAuditStore? auditStore,
  }) : _auditStore = auditStore;

  final IClientTokenRepository _repository;
  final ITokenAuditStore? _auditStore;

  Future<Result<ClientTokenUpdateResult>> call(
    String tokenId,
    ClientTokenCreateRequest request, {
    int? expectedVersion,
  }) async {
    if (tokenId.trim().isEmpty) {
      return Failure(domain.ValidationFailure('token_id is required'));
    }

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

    final result = await _repository.updateToken(
      tokenId,
      request,
      expectedVersion: expectedVersion,
    );
    if (result.isSuccess()) {
      await _recordRotateAuditEvent(tokenId, request.clientId);
    }
    return result;
  }

  Future<void> _recordRotateAuditEvent(String tokenId, String clientId) async {
    if (_auditStore == null) {
      return;
    }
    try {
      await _auditStore.record(
        TokenAuditEvent(
          eventType: TokenAuditEventType.rotate,
          timestamp: DateTime.now().toUtc(),
          tokenId: tokenId,
          clientId: clientId,
        ),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to record client token rotation audit event',
        name: 'update_client_token_use_case',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
