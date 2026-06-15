import 'package:plug_agente/application/validation/query_validation_messages.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_query_config_source.dart';
import 'package:plug_agente/domain/validation/sql_validator.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class ExecutePlaygroundQuery {
  ExecutePlaygroundQuery(
    this._databaseGateway,
    this._queryConfigSource,
    this._uuid,
  );
  final IDatabaseGateway _databaseGateway;
  final IQueryConfigSource _queryConfigSource;
  final Uuid _uuid;

  Future<Result<QueryResponse>> call(
    String query, {
    String? configId,
    QueryPaginationRequest? pagination,
    SqlHandlingMode sqlHandlingMode = SqlHandlingMode.managed,
    CancellationToken? cancellationToken,
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

            return _databaseGateway.executeQuery(
              request,
              timeout: ConnectionConstants.defaultQueryTimeout,
              cancellationToken: cancellationToken,
            );
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
    return _queryConfigSource.resolveConfigForQuery(configId);
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
