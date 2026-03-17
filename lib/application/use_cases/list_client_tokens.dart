import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:result_dart/result_dart.dart';

class ListClientTokens {
  ListClientTokens(this._repository);

  final IClientTokenRepository _repository;

  Future<Result<List<ClientTokenSummary>>> call({
    ClientTokenListQuery? query,
  }) {
    return _repository.listTokens(query: query);
  }
}
