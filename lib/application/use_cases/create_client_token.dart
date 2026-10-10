import 'dart:developer' as developer;

import 'package:plug_agente/application/client_tokens/client_token_payload_parser.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_creation_result.dart';
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

  Future<Result<String>> call(ClientTokenCreateRequest request) =>
      _create(request, () => _repository.createToken(request));

  Future<Result<ClientTokenCreationResult>> createWithIdentity(ClientTokenCreateRequest request) =>
      _create(request, () => _repository.createTokenWithIdentity(request), tokenIdOf: (created) => created.tokenId);

  Future<Result<T>> _create<T extends Object>(
    ClientTokenCreateRequest request,
    Future<Result<T>> Function() write, {
    String Function(T)? tokenIdOf,
  }) async {
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

    final result = await write();
    if (result.isSuccess()) {
      await _recordCreateAuditEvent(request, tokenId: tokenIdOf?.call(result.getOrThrow()));
    }
    return result;
  }

  Future<void> _recordCreateAuditEvent(ClientTokenCreateRequest request, {String? tokenId}) async {
    if (_auditStore == null) {
      return;
    }
    try {
      await _auditStore.record(
        TokenAuditEvent(
          eventType: TokenAuditEventType.create,
          timestamp: DateTime.now().toUtc(),
          clientId: request.clientId,
          tokenId: tokenId,
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
