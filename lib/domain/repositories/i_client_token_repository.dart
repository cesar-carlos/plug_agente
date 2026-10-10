import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_creation_result.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_page.dart';
import 'package:plug_agente/domain/entities/client_token_secret_lookup.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:result_dart/result_dart.dart';

/// Persists token mutations and invalidates affected authorization caches
/// after confirmed writes, before awaiting secret cleanup or returning success.
abstract class IClientTokenRepository {
  Future<Result<ClientTokenSummary>> getTokenById(String tokenId);

  Future<Result<ClientTokenSummary>> getTokenByHash(String tokenHash);

  /// Resolves authorization metadata without reading the credential value from
  /// secure storage. Intended for inbound policy checks only.
  Future<Result<ClientTokenSummary>> getTokenPolicySummaryByHash(String tokenHash);

  Future<Result<ClientTokenSecretLookup>> getTokenSecret(String tokenId);

  Future<Result<String>> createToken(ClientTokenCreateRequest request);
  Future<Result<ClientTokenCreationResult>> createTokenWithIdentity(ClientTokenCreateRequest request);
  Future<Result<ClientTokenUpdateResult>> updateToken(
    String tokenId,
    ClientTokenCreateRequest request, {
    int? expectedVersion,
  });
  Future<Result<List<ClientTokenSummary>>> listTokens({
    ClientTokenListQuery? query,
  });
  Future<Result<ClientTokenPage>> listTokenPage({required ClientTokenListQuery query});
  Future<Result<int>> countActiveTokens();
  Future<Result<void>> revokeToken(String tokenId);
  Future<Result<void>> deleteToken(String tokenId);
}
