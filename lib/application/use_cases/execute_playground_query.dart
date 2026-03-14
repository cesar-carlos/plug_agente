import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
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

  Future<Result<QueryResponse>> call(
    String query, {
    QueryPaginationRequest? pagination,
  }) async {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return Failure(domain.ValidationFailure('A query não pode estar vazia'));
    }

    final validation = SqlValidator.validateSelectQuery(trimmedQuery);
    final expectMultipleResults = SqlValidator.containsMultipleStatements(
      trimmedQuery,
    );
    final resolvedPagination = _resolvePagination(
      trimmedQuery,
      pagination,
      expectMultipleResults: expectMultipleResults,
    );

    return validation.fold(
      (_) async {
        final configResult = await _configRepository.getCurrentConfig();

        return configResult.fold(
          (config) async {
            final request = QueryRequest(
              id: _uuid.v4(),
              agentId: config.agentId,
              query: query,
              timestamp: DateTime.now(),
              pagination: resolvedPagination,
              expectMultipleResults: expectMultipleResults,
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
        return Failure(failure);
      },
    );
  }

  QueryPaginationRequest? _resolvePagination(
    String query,
    QueryPaginationRequest? pagination, {
    required bool expectMultipleResults,
  }) {
    if (pagination == null || expectMultipleResults) {
      return null;
    }

    final paginationPlan = SqlValidator.validatePaginationQuery(query);
    if (paginationPlan.isError()) {
      return null;
    }

    final plan = paginationPlan.getOrNull()!;
    return QueryPaginationRequest(
      page: pagination.page,
      pageSize: pagination.pageSize,
      cursor: pagination.cursor,
      queryHash: plan.queryFingerprint,
      orderBy: plan.orderBy,
      lastRowValues: pagination.lastRowValues,
      offset: pagination.isCursorMode ? pagination.offset : null,
    );
  }
}
