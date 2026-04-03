import 'dart:developer' as developer;

import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_paginated_sql_builder.dart';

/// SQL and parameters ready for `OdbcService` after optional pagination rewrite.
class OdbcPreparedQueryExecution {
  const OdbcPreparedQueryExecution({
    required this.sql,
    required this.parameters,
  });

  final String sql;
  final Map<String, dynamic>? parameters;
}

/// Pagination validation and SQL preparation for `OdbcDatabaseGateway`.
///
/// Keeps gateway thinner and allows direct unit tests of these rules.
class OdbcGatewayQueryPreparation {
  OdbcGatewayQueryPreparation._();
  static const int maxNamedParameterCount = 5;

  static domain.ValidationFailure? validatePaginationForDatabase(
    QueryRequest request,
    DatabaseType databaseType,
  ) {
    if (request.preserveSql && request.pagination != null) {
      return domain.ValidationFailure(
        'preserve_sql cannot be combined with managed pagination',
      );
    }

    final pagination = request.pagination;
    if (pagination == null) {
      return null;
    }

    if (SqlValidator.containsTopLevelPaginationClause(request.query)) {
      return domain.ValidationFailure(
        'Paginated requests cannot include LIMIT/OFFSET/FETCH in SQL; '
        'use options.page/page_size or options.cursor',
      );
    }

    final requiresExplicitOrderBy =
        databaseType == DatabaseType.sqlServer || databaseType == DatabaseType.sybaseAnywhere;
    if (requiresExplicitOrderBy && pagination.orderBy.isEmpty) {
      return domain.ValidationFailure(
        'Page-offset pagination requires an explicit ORDER BY for '
        'SQL Server and SQL Anywhere',
      );
    }

    return null;
  }

  static OdbcPreparedQueryExecution prepareQueryExecution(
    QueryRequest request,
    DatabaseConfig databaseConfig,
  ) {
    if (request.preserveSql) {
      return OdbcPreparedQueryExecution(
        sql: request.query,
        parameters: request.parameters,
      );
    }

    final pagination = request.pagination;
    if (pagination == null) {
      return OdbcPreparedQueryExecution(
        sql: request.query,
        parameters: request.parameters,
      );
    }

    final sql = pagination.usesStableCursor
        ? OdbcPaginatedSqlBuilder.buildCursorPaginatedSql(
            request.query,
            databaseConfig.databaseType,
            pagination,
          )
        : OdbcPaginatedSqlBuilder.buildOffsetPaginatedSql(
            request.query,
            databaseConfig.databaseType,
            pagination,
          );
    return OdbcPreparedQueryExecution(
      sql: sql,
      parameters: request.parameters,
    );
  }

  static domain.ValidationFailure? validateQueryExecutionMode(
    QueryRequest request,
    OdbcPreparedQueryExecution preparedExecution,
  ) {
    if (!request.expectMultipleResults) {
      return null;
    }
    if (request.pagination != null) {
      return domain.ValidationFailure(
        'Multi-result execution cannot be combined with pagination',
      );
    }
    if (preparedExecution.parameters?.isNotEmpty ?? false) {
      return domain.ValidationFailure(
        'Multi-result execution is not supported with named parameters',
      );
    }
    return null;
  }

  static domain.ValidationFailure? validateParameterCount(
    OdbcPreparedQueryExecution preparedExecution,
  ) {
    final count = preparedExecution.parameters?.length ?? 0;
    if (count <= maxNamedParameterCount) {
      return null;
    }

    return domain.ValidationFailure(
      'Query uses $count named parameters; '
      'the current runtime supports up to $maxNamedParameterCount. '
      'Split the query or use positional literals.',
    );
  }

  static bool shouldUseMultiResultExecution(
    QueryRequest request,
    OdbcPreparedQueryExecution preparedExecution,
  ) {
    if (!request.expectMultipleResults) {
      return false;
    }
    if (request.pagination != null) {
      return false;
    }
    return !(preparedExecution.parameters?.isNotEmpty ?? false);
  }

  static void maybeLogPaginatedSqlRewrite({
    required FeatureFlags? featureFlags,
    required QueryRequest request,
    required DatabaseConfig databaseConfig,
    required OdbcPreparedQueryExecution preparedExecution,
  }) {
    if (featureFlags == null || !featureFlags.enableOdbcPaginatedSqlDebugLog) {
      return;
    }
    if (request.pagination == null || request.preserveSql) {
      return;
    }
    final original = request.query.trim();
    final rewritten = preparedExecution.sql.trim();
    if (original == rewritten) {
      return;
    }
    developer.log(
      'Paginated SQL (${databaseConfig.databaseType.name}): $rewritten',
      name: 'odbc_database_gateway',
    );
  }
}
