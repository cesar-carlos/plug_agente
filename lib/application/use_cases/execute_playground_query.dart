import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/query_request.dart';
import '../../domain/entities/query_response.dart';
import '../../domain/repositories/i_database_gateway.dart';
import '../../domain/repositories/i_agent_config_repository.dart';
import '../../domain/errors/failures.dart' as domain;

class ExecutePlaygroundQuery {
  final IDatabaseGateway _databaseGateway;
  final IAgentConfigRepository _configRepository;
  final Uuid _uuid;

  ExecutePlaygroundQuery(this._databaseGateway, this._configRepository, this._uuid);

  Future<Result<QueryResponse>> call(String query) async {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return Failure(domain.ValidationFailure('A query não pode estar vazia'));
    }

    if (!trimmedQuery.toUpperCase().startsWith('SELECT')) {
      return Failure(
        domain.ValidationFailure(
          'Apenas consultas SELECT são permitidas. '
          'Outras operações (INSERT, UPDATE, DELETE, etc.) não são suportadas.',
        ),
      );
    }

    final configResult = await _configRepository.getCurrentConfig();

    return configResult.fold(
      (config) async {
        final request = QueryRequest(id: _uuid.v4(), agentId: config.agentId, query: query, timestamp: DateTime.now());

        return await _databaseGateway.executeQuery(request);
      },
      (failure) {
        final failureMessage = failure is domain.Failure ? failure.message : failure.toString();
        return Failure(domain.ConfigurationFailure('Configuração não encontrada: $failureMessage'));
      },
    );
  }
}
