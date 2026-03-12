import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_data_source.dart';
import 'package:result_dart/result_dart.dart';

class ClientTokenRepository implements IClientTokenRepository {
  ClientTokenRepository(
    this._dataSource,
    this._configRepository,
  );

  final ClientTokenDataSource _dataSource;
  final IAgentConfigRepository _configRepository;

  @override
  Future<Result<String>> createToken(ClientTokenCreateRequest request) async {
    final serverUrlResult = await _resolveServerUrl();
    return serverUrlResult.fold(
      (serverUrl) => _dataSource.createToken(serverUrl, request),
      Failure.new,
    );
  }

  @override
  Future<Result<List<ClientTokenSummary>>> listTokens() async {
    final serverUrlResult = await _resolveServerUrl();
    return serverUrlResult.fold(
      _dataSource.listTokens,
      Failure.new,
    );
  }

  @override
  Future<Result<void>> revokeToken(String tokenId) async {
    final serverUrlResult = await _resolveServerUrl();
    return serverUrlResult.fold(
      (serverUrl) => _dataSource.revokeToken(serverUrl, tokenId),
      Failure.new,
    );
  }

  Future<Result<String>> _resolveServerUrl() async {
    final configResult = await _configRepository.getCurrentConfig();
    return configResult.fold((config) async {
      final serverUrl = config.serverUrl.trim();
      if (serverUrl.isEmpty) {
        return Failure(
          domain.ConfigurationFailure(
            'Server URL is not configured for client token operations',
          ),
        );
      }
      return Success(serverUrl);
    }, (failure) async => Failure(failure));
  }
}
