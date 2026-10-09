import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:result_dart/result_dart.dart';

class CountActiveClientTokens {
  CountActiveClientTokens(this._repository);

  final IClientTokenRepository _repository;

  Future<Result<int>> call() => _repository.countActiveTokens();
}
