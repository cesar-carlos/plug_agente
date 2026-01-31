import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class ExecutePlaygroundQuery {
  ExecutePlaygroundQuery(
    this._databaseGateway,
    this._configRepository,
    this._uuid,
  );
  final IDatabaseGateway _databaseGateway;
  final IAgentConfigRepository _configRepository;
  final Uuid _uuid;

  Future<Result<QueryResponse>> call(String query) async {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return Failure(domain.ValidationFailure('A query não pode estar vazia'));
    }

    // Validar segurança da query
    final validation = SqlValidator.validateSelectQuery(trimmedQuery);

    // Encadear validação com execução usando fold
    return validation.fold(
      (_) async {
        // Validação sucesso, buscar config e executar
        final configResult = await _configRepository.getCurrentConfig();

        return configResult.fold(
          (config) async {
            final request = QueryRequest(
              id: _uuid.v4(),
              agentId: config.agentId,
              query: query,
              timestamp: DateTime.now(),
            );

            return _databaseGateway.executeQuery(request);
          },
          (failure) {
            final failureMessage = failure is domain.Failure
                ? failure.message
                : failure.toString();
            return Failure(
              domain.ConfigurationFailure(
                'Configuração não encontrada: $failureMessage',
              ),
            );
          },
        );
      },
      (failure) {
        // Validação falhou - retornar Failure de validação
        return Failure(failure);
      },
    );
  }
}
