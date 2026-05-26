import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/validation/query_validation_messages.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/domain/entities/config.dart';
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
    Object configContext,
    this._uuid,
  ) : _activeConfigResolver = configContext is ActiveConfigResolver ? configContext : null,
      _configRepository = configContext is IAgentConfigRepository ? configContext : null;
  final IDatabaseGateway _databaseGateway;
  final ActiveConfigResolver? _activeConfigResolver;
  final IAgentConfigRepository? _configRepository;
  final Uuid _uuid;

  Future<Result<QueryResponse>> call(
    String query, {
    String? configId,
    QueryPaginationRequest? pagination,
    SqlHandlingMode sqlHandlingMode = SqlHandlingMode.managed,
  }) async {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return Failure(
        domain.ValidationFailure(QueryValidationMessages.queryCannotBeEmpty),
      );
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
        final configResult = await _resolveConfig(configId);

        return configResult.fold(
          (config) async {
            final request = QueryRequest(
              id: _uuid.v4(),
              agentId: config.agentId,
              configId: config.id,
              query: query,
              timestamp: DateTime.now(),
              pagination: resolvedPagination,
              expectMultipleResults: expectMultipleResults,
              sqlHandlingMode: sqlHandlingMode,
            );

            return _databaseGateway.executeQuery(request);
          },
          (failure) {
            final failureMessage = failure is domain.Failure ? failure.message : failure.toString();
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

  Future<Result<Config>> _resolveConfig(String? configId) {
    final resolver = _activeConfigResolver;
    final normalized = configId?.trim();
    if (resolver != null) {
      if (normalized != null && normalized.isNotEmpty) {
        return resolver.resolveExplicit(
          normalized,
          metadataOnly: true,
        );
      }
      return resolver.resolveActiveOrFallback(metadataOnly: true);
    }

    if (normalized != null && normalized.isNotEmpty) {
      return _configRepository!.getByIdMetadata(normalized);
    }
    return _configRepository!.getCurrentConfigMetadata();
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
