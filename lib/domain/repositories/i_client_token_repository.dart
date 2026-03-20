import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:result_dart/result_dart.dart';

abstract class IClientTokenRepository {
  Future<ClientTokenSummary?> getTokenById(String tokenId);

  Future<Result<String>> createToken(ClientTokenCreateRequest request);
  Future<Result<ClientTokenUpdateResult>> updateToken(
    String tokenId,
    ClientTokenCreateRequest request, {
    int? expectedVersion,
  });
  Future<Result<List<ClientTokenSummary>>> listTokens({
    ClientTokenListQuery? query,
  });
  Future<Result<void>> revokeToken(String tokenId);
  Future<Result<void>> deleteToken(String tokenId);
}
