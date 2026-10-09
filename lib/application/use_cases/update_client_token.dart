import 'dart:developer' as developer;

import 'package:plug_agente/application/client_tokens/client_token_payload_parser.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:result_dart/result_dart.dart';

const _logName = 'update_client_token_use_case';

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

    final payloadValidationError = validateClientTokenPayload(request.payload);
    if (payloadValidationError != null) {
      return Failure(
        domain.ValidationFailure(
          switch (payloadValidationError) {
            ClientTokenPayloadValidationError.databaseMustBeString => 'payload.database must be a string',
            ClientTokenPayloadValidationError.databaseCannotBeEmpty => 'payload.database must not be empty',
            ClientTokenPayloadValidationError.runtimeRestrictionsInvalid =>
              'Runtime token restrictions must use strings or arrays of strings',
          },
        ),
      );
    }

    if (request.usesGlobalScope) {
      if (!request.effectiveGlobalPermissions.hasAnyPermission) {
        return Failure(
          domain.ValidationFailure(
            'At least one global permission is required when all_tables or all_views is enabled',
          ),
        );
      }
    } else if (request.effectiveRules.isEmpty) {
      return Failure(
        domain.ValidationFailure(
          'At least one rule is required when global scope is disabled',
        ),
      );
    }

    final result = await _repository.updateToken(
      tokenId,
      request,
      expectedVersion: expectedVersion,
    );
    if (result.isSuccess()) {
      final updateResult = result.getOrNull();
      if (updateResult != null) {
        await _handleSuccessfulUpdate(
          tokenId: tokenId,
          clientId: request.normalizedClientId,
          updateResult: updateResult,
        );
      }
    }
    return result;
  }

  Future<void> _handleSuccessfulUpdate({
    required String tokenId,
    required String clientId,
    required ClientTokenUpdateResult updateResult,
  }) async {
    switch (updateResult.outcome) {
      case ClientTokenUpdateOutcome.unchanged:
        // No persisted change — keep caches and audit trail untouched.
        return;
      case ClientTokenUpdateOutcome.metadataOnly:
        // The repository refreshes cached identity without rotating the credential.
        await _recordAuditEvent(
          tokenId: tokenId,
          clientId: clientId,
          eventType: TokenAuditEventType.metadataUpdate,
        );
        return;
      case ClientTokenUpdateOutcome.rotated:
        await _recordAuditEvent(
          tokenId: tokenId,
          clientId: clientId,
          eventType: TokenAuditEventType.rotate,
        );
        return;
    }
  }

  Future<void> _recordAuditEvent({
    required String tokenId,
    required String clientId,
    required TokenAuditEventType eventType,
  }) async {
    if (_auditStore == null) {
      return;
    }
    try {
      await _auditStore.record(
        TokenAuditEvent(
          eventType: eventType,
          timestamp: DateTime.now().toUtc(),
          tokenId: tokenId,
          clientId: clientId,
        ),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to record client token update audit event',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
