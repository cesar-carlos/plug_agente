import 'package:plug_agente/domain/entities/client_token_secret_lookup.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:result_dart/result_dart.dart';

class GetClientTokenSecret {
  GetClientTokenSecret(this._repository);

  final IClientTokenRepository _repository;

  Future<Result<ClientTokenSecretLookup>> call(String tokenId) async {
    if (tokenId.trim().isEmpty) {
      return Failure(domain.ValidationFailure('token_id is required'));
    }

    return _repository.getTokenSecret(tokenId);
  }
}
