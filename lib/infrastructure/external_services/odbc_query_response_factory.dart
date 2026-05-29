import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_result_mapper.dart';
import 'package:uuid/uuid.dart';

/// Builds agent [QueryResponse] objects from `odbc_fast` results.
///
/// Extracted from `OdbcDatabaseGateway` to isolate the (pure) result→response
/// transformation, pagination shaping, DML affected-row semantics, and
/// multi-result aggregation behind a focused, unit-testable surface.
final class OdbcQueryResponseFactory {
  OdbcQueryResponseFactory._();

  static const Uuid _uuid = Uuid();

  static final RegExp _dmlPrefix = RegExp(
    r'^(insert|update|delete|merge)\s',
    caseSensitive: false,
  );

  /// Returns true when the query is DML so that `affectedRows` carries
  /// meaningful semantics. SELECT/WITH return false to avoid misleading row
  /// count reporting.
  static bool isDmlQuery(String query) => _dmlPrefix.hasMatch(query.trimLeft());

  static QueryResponse fromSingleResult(
    QueryRequest request,
    QueryResult queryResult, {
    DateTime? startedAt,
  }) {
    final rawData = OdbcGatewayQueryResultMapper.convertQueryResultToMaps(
      queryResult,
    );
    final paginationResponse = OdbcGatewayQueryResultMapper.buildPaginationResponse(
      request.pagination,
      rawData,
    );
    final data = paginationResponse == null ? rawData : rawData.take(request.pagination!.pageSize).toList();

    final isDml = isDmlQuery(request.query);
    final finishedAt = DateTime.now();
    return QueryResponse(
      id: _uuid.v4(),
      requestId: request.id,
      agentId: request.agentId,
      data: data,
      // rowCount carries SQLRowCount for DML (affected rows) and rows-fetched
      // for SELECT; data.length is always 0 for plain DML without OUTPUT/RETURNING.
      affectedRows: isDml ? queryResult.rowCount : null,
      startedAt: startedAt,
      timestamp: finishedAt,
      columnMetadata: OdbcGatewayQueryResultMapper.buildColumnMetadata(
        queryResult.columns,
      ),
      pagination: paginationResponse,
    );
  }

  /// Builds a multi-result [QueryResponse]. Top-level
  /// [QueryResponse.affectedRows] sums row-count items when present; otherwise
  /// falls back to the first result set row count (legacy single-field
  /// compatibility for RPC).
  static QueryResponse fromMultiResult(
    QueryRequest request,
    QueryResultMulti queryResult, {
    DateTime? startedAt,
  }) {
    final resultSets = <QueryResultSet>[];
    final items = <QueryResponseItem>[];
    var resultSetIndex = 0;
    var totalAffectedRows = 0;

    for (var itemIndex = 0; itemIndex < queryResult.items.length; itemIndex++) {
      final item = queryResult.items[itemIndex];
      if (item.resultSet != null) {
        final resultSet = QueryResultSet(
          index: resultSetIndex,
          rows: OdbcGatewayQueryResultMapper.convertQueryResultToMaps(
            item.resultSet!,
          ),
          rowCount: item.resultSet!.rowCount,
          columnMetadata: OdbcGatewayQueryResultMapper.buildColumnMetadata(
            item.resultSet!.columns,
          ),
        );
        resultSets.add(resultSet);
        items.add(
          QueryResponseItem.resultSet(
            index: itemIndex,
            resultSet: resultSet,
          ),
        );
        resultSetIndex++;
        continue;
      }

      final rowCount = item.rowCount ?? 0;
      totalAffectedRows += rowCount;
      items.add(
        QueryResponseItem.rowCount(
          index: itemIndex,
          rowCount: rowCount,
        ),
      );
    }

    final primaryResultSet = resultSets.isNotEmpty
        ? resultSets.first
        : const QueryResultSet(index: 0, rows: [], rowCount: 0);

    return QueryResponse(
      id: _uuid.v4(),
      requestId: request.id,
      agentId: request.agentId,
      data: primaryResultSet.rows,
      affectedRows: totalAffectedRows > 0 ? totalAffectedRows : primaryResultSet.rowCount,
      startedAt: startedAt,
      timestamp: DateTime.now(),
      columnMetadata: primaryResultSet.columnMetadata,
      resultSets: resultSets,
      items: items,
    );
  }
}
