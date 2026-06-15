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
    if (result.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    return List<Map<String, dynamic>>.generate(
      result.rows.length,
      (rowIndex) {
        return result.rowAsMap(rowIndex);
      },
      growable: false,
    );
  }

  static List<Map<String, dynamic>> buildColumnMetadataFromNames(
    List<String> columns,
  ) {
    return columns.map((column) => <String, dynamic>{'name': column}).toList(growable: false);
  }

  static List<Map<String, dynamic>> buildColumnMetadata(
    QueryResult result,
  ) {
    final richMetadata = result.columnsMetadata;
    if (richMetadata != null && richMetadata.isNotEmpty) {
      return richMetadata
          .map(
            (metadata) => <String, dynamic>{
              'name': metadata.name,
              'odbc_type': metadata.odbcType,
            },
          )
          .toList(growable: false);
    }
    return buildColumnMetadataFromNames(result.columns);
  }
}
