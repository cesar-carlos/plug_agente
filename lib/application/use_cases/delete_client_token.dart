import 'dart:developer' as developer;

import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:result_dart/result_dart.dart';

class DeleteClientToken {
  DeleteClientToken(
    this._repository, {
    ITokenAuditStore? auditStore,
  }) : _auditStore = auditStore;

  final IClientTokenRepository _repository;
  final ITokenAuditStore? _auditStore;

  Future<Result<void>> call(String tokenId) async {
    if (tokenId.trim().isEmpty) {
      return Failure(domain.ValidationFailure('tokenId is required'));
    }

    final result = await _repository.deleteToken(tokenId);
    if (result.isSuccess()) {
      await _recordDeleteAuditEvent(tokenId);
    }
    return result;
  }

  Future<void> _recordDeleteAuditEvent(String tokenId) async {
    if (_auditStore == null) {
      return;
    }
    try {
      await _auditStore.record(
        TokenAuditEvent(
          eventType: TokenAuditEventType.delete,
          timestamp: DateTime.now().toUtc(),
          tokenId: tokenId,
        ),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to record client token delete audit event',
        name: 'delete_client_token_use_case',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
