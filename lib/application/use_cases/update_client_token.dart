import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:result_dart/result_dart.dart';

class UpdateClientToken {
  UpdateClientToken(this._repository);

  final IClientTokenRepository _repository;

  Future<Result<void>> call(
    String tokenId,
    ClientTokenCreateRequest request,
  ) async {
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

    return _repository.updateToken(tokenId, request);
  }
}
