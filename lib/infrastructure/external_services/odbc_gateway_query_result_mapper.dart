import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_paginated_sql_builder.dart';

/// Maps `odbc_fast` query results into agent `QueryResponse` building blocks.
///
/// Extracted from `OdbcDatabaseGateway` for unit testing and readability.
class OdbcGatewayQueryResultMapper {
  OdbcGatewayQueryResultMapper._();

  static QueryPaginationInfo? buildPaginationResponse(
    QueryPaginationRequest? pagination,
    List<Map<String, dynamic>> rawData,
  ) {
    if (pagination == null) {
      return null;
    }

    final rawRowCount = rawData.length;
    final hasNextPage = rawRowCount > pagination.pageSize;
    final returnedRows = hasNextPage ? pagination.pageSize : rawRowCount;
    final pageData = rawData.take(returnedRows).toList();
    return QueryPaginationInfo(
      page: pagination.page,
      pageSize: pagination.pageSize,
      returnedRows: returnedRows,
      hasNextPage: hasNextPage,
      hasPreviousPage: pagination.page > 1,
      currentCursor: pagination.cursor,
      nextCursor: hasNextPage
          ? OdbcPaginatedSqlBuilder.buildNextCursorToken(
              pagination: pagination,
              pageData: pageData,
            )
          : null,
    );
  }

  static List<Map<String, dynamic>> convertQueryResultToMaps(
    QueryResult result,
  ) {
    final columns = result.columns;
    final colCount = columns.length;
    final rows = result.rows;
    final rowCount = rows.length;
    if (rowCount == 0) {
      return <Map<String, dynamic>>[];
    }
    if (colCount == 0) {
      return List<Map<String, dynamic>>.generate(
        rowCount,
        (_) => <String, dynamic>{},
        growable: false,
      );
    }
    return List<Map<String, dynamic>>.generate(
      rowCount,
      (int r) {
        final row = rows[r];
        final map = <String, dynamic>{};
        for (var i = 0; i < colCount; i++) {
          map[columns[i]] = row[i];
        }
        return map;
      },
      growable: false,
    );
  }

  static List<Map<String, dynamic>> buildColumnMetadata(
    List<String> columns,
  ) {
    return columns.map((column) => <String, dynamic>{'name': column}).toList(growable: false);
  }
}
