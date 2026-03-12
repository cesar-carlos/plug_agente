import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:result_dart/result_dart.dart';

class RevokeClientToken {
  RevokeClientToken(
    this._repository, {
    ITokenAuditStore? auditStore,
  }) : _auditStore = auditStore;

  final IClientTokenRepository _repository;
  final ITokenAuditStore? _auditStore;

  Future<Result<void>> call(String tokenId) async {
    if (tokenId.trim().isEmpty) {
      return Failure(domain.ValidationFailure('tokenId is required'));
    }

    final result = await _repository.revokeToken(tokenId);
    result.fold(
      (_) {
        _auditStore?.record(
          TokenAuditEvent(
            eventType: TokenAuditEventType.revoke,
            timestamp: DateTime.now().toUtc(),
            tokenId: tokenId,
          ),
        );
      },
      (_) {},
    );
    return result;
  }
}
