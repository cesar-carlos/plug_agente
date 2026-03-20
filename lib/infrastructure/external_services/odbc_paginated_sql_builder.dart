import 'dart:developer' as developer;

import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';

/// Builds dialect-specific SQL for managed pagination (offset and cursor).
///
/// Keeps pagination SQL out of the ODBC gateway for easier testing.
final class OdbcPaginatedSqlBuilder {
  OdbcPaginatedSqlBuilder._();

  static String buildOffsetPaginatedSql(
    String originalSql,
    DatabaseType databaseType,
    QueryPaginationRequest pagination,
  ) {
    final trimmedSql = SqlValidator.stripTopLevelOrderBy(originalSql);
    final orderByClause = pagination.orderBy.isEmpty
        ? null
        : buildOrderByClause(pagination.orderBy);
    return switch (databaseType) {
      DatabaseType.postgresql =>
        '''
SELECT *
FROM (
  $trimmedSql
) AS plug_paginated_source
${orderByClause != null ? 'ORDER BY $orderByClause' : ''}
LIMIT ${pagination.fetchSizeWithLookAhead} OFFSET ${pagination.offset}
''',
      DatabaseType.sqlServer =>
        '''
SELECT *
FROM (
  $trimmedSql
) AS plug_paginated_source
ORDER BY ${orderByClause ?? '(SELECT NULL)'}
OFFSET ${pagination.offset} ROWS FETCH NEXT ${pagination.fetchSizeWithLookAhead} ROWS ONLY
''',
      DatabaseType.sybaseAnywhere =>
        '''
SELECT TOP ${pagination.fetchSizeWithLookAhead} START AT ${pagination.offset + 1} *
FROM (
  $trimmedSql
) AS plug_paginated_source
ORDER BY ${orderByClause ?? '(SELECT NULL)'}
''',
    };
  }

  static String buildCursorPaginatedSql(
    String originalSql,
    DatabaseType databaseType,
    QueryPaginationRequest pagination,
  ) {
    final trimmedSql = SqlValidator.stripTopLevelOrderBy(originalSql);
    final orderByClause = buildOrderByClause(pagination.orderBy);
    final whereClause = buildKeysetWhereClause(
      pagination.orderBy,
      pagination.lastRowValues,
      databaseType,
    );

    return switch (databaseType) {
      DatabaseType.postgresql =>
        '''
SELECT *
FROM (
  $trimmedSql
) AS plug_paginated_source
WHERE $whereClause
ORDER BY $orderByClause
LIMIT ${pagination.fetchSizeWithLookAhead}
''',
      DatabaseType.sqlServer =>
        '''
SELECT *
FROM (
  $trimmedSql
) AS plug_paginated_source
WHERE $whereClause
ORDER BY $orderByClause
OFFSET 0 ROWS FETCH NEXT ${pagination.fetchSizeWithLookAhead} ROWS ONLY
''',
      DatabaseType.sybaseAnywhere =>
        '''
SELECT TOP ${pagination.fetchSizeWithLookAhead} *
FROM (
  $trimmedSql
) AS plug_paginated_source
WHERE $whereClause
ORDER BY $orderByClause
''',
    };
  }

  static String buildOrderByClause(List<QueryPaginationOrderTerm> orderBy) {
    return orderBy
        .map(
          (term) => '${term.expression}${term.descending ? ' DESC' : ' ASC'}',
        )
        .join(', ');
  }

  static String buildKeysetWhereClause(
    List<QueryPaginationOrderTerm> orderBy,
    List<dynamic> lastRowValues,
    DatabaseType databaseType,
  ) {
    final disjunctions = <String>[];

    for (var i = 0; i < orderBy.length; i++) {
      final conjunctions = <String>[];
      for (var j = 0; j < i; j++) {
        conjunctions.add(
          '${orderBy[j].expression} = '
          '${toSqlLiteral(lastRowValues[j], databaseType)}',
        );
      }

      final operator = orderBy[i].descending ? '<' : '>';
      conjunctions.add(
        '${orderBy[i].expression} $operator '
        '${toSqlLiteral(lastRowValues[i], databaseType)}',
      );
      disjunctions.add('(${conjunctions.join(' AND ')})');
    }

    return disjunctions.join(' OR ');
  }

  static String? buildNextCursorToken({
    required QueryPaginationRequest pagination,
    required List<Map<String, dynamic>> pageData,
  }) {
    if (pageData.isEmpty) {
      return null;
    }
    if (pagination.orderBy.isEmpty) {
      return null;
    }

    final lastRow = pageData.last;
    final lastRowValues = <dynamic>[];
    for (final term in pagination.orderBy) {
      if (!lastRow.containsKey(term.lookupKey)) {
        developer.log(
          'Unable to derive cursor key "${term.lookupKey}" from page data',
          name: 'odbc_paginated_sql_builder',
          level: 900,
        );
        return null;
      }
      lastRowValues.add(lastRow[term.lookupKey]);
    }

    return QueryPaginationCursor(
      page: pagination.page + 1,
      pageSize: pagination.pageSize,
      queryHash: pagination.queryHash,
      orderBy: pagination.orderBy,
      lastRowValues: lastRowValues,
    ).toToken();
  }

  static String toSqlLiteral(dynamic value, DatabaseType databaseType) {
    if (value == null) {
      throw StateError('Cursor pagination does not support null order values');
    }
    if (value is num) {
      return value.toString();
    }
    if (value is bool) {
      return switch (databaseType) {
        DatabaseType.postgresql => value ? 'TRUE' : 'FALSE',
        DatabaseType.sqlServer ||
        DatabaseType.sybaseAnywhere => value ? '1' : '0',
      };
    }
    if (value is DateTime) {
      return "'${value.toUtc().toIso8601String().replaceAll("'", "''")}'";
    }
    final stringValue = value.toString().replaceAll("'", "''");
    return "'$stringValue'";
  }
}
