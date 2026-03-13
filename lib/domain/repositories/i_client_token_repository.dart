import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:result_dart/result_dart.dart';

abstract class IClientTokenRepository {
  Future<Result<String>> createToken(ClientTokenCreateRequest request);
  Future<Result<List<ClientTokenSummary>>> listTokens();
  Future<Result<void>> revokeToken(String tokenId);
  Future<Result<void>> deleteToken(String tokenId);
}
