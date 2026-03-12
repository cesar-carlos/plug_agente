import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:result_dart/result_dart.dart';

class RevokeClientToken {
  RevokeClientToken(this._repository);

  final IClientTokenRepository _repository;

  Future<Result<void>> call(String tokenId) async {
    if (tokenId.trim().isEmpty) {
      return Failure(domain.ValidationFailure('tokenId is required'));
    }

    return _repository.revokeToken(tokenId);
  }
}
