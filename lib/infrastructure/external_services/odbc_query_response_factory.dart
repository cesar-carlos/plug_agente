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
        queryResult,
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
    final builder = multiResultBuilder(request, startedAt: startedAt);
    queryResult.items.forEach(builder.addItemSync);
    return builder.build();
  }

  static OdbcMultiResultResponseBuilder multiResultBuilder(
    QueryRequest request, {
    DateTime? startedAt,
  }) {
    return OdbcMultiResultResponseBuilder(
      request: request,
      startedAt: startedAt,
      uuid: _uuid,
    );
  }
}

/// Incrementally assembles a multi-result [QueryResponse] while streaming items.
final class OdbcMultiResultResponseBuilder {
  OdbcMultiResultResponseBuilder({
    required QueryRequest request,
    required Uuid uuid,
    DateTime? startedAt,
  }) : _request = request,
       _uuid = uuid,
       _startedAt = startedAt;

  final QueryRequest _request;
  final Uuid _uuid;
  final DateTime? _startedAt;
  final List<QueryResultSet> _resultSets = <QueryResultSet>[];
  final List<QueryResponseItem> _items = <QueryResponseItem>[];
  var _resultSetIndex = 0;
  var _totalAffectedRows = 0;
  var _itemIndex = 0;

  Future<void> addItem(QueryResultMultiItem item) async {
    addItemSync(item);
  }

  void addItemSync(QueryResultMultiItem item) {
    final currentIndex = _itemIndex++;
    if (item.resultSet != null) {
      final resultSet = QueryResultSet(
        index: _resultSetIndex,
        rows: OdbcGatewayQueryResultMapper.convertQueryResultToMaps(
          item.resultSet!,
        ),
        rowCount: item.resultSet!.rowCount,
        columnMetadata: OdbcGatewayQueryResultMapper.buildColumnMetadata(
          item.resultSet!,
        ),
      );
      _resultSets.add(resultSet);
      _items.add(
        QueryResponseItem.resultSet(
          index: currentIndex,
          resultSet: resultSet,
        ),
      );
      _resultSetIndex++;
      return;
    }

    final rowCount = item.rowCount ?? 0;
    _totalAffectedRows += rowCount;
    _items.add(
      QueryResponseItem.rowCount(
        index: currentIndex,
        rowCount: rowCount,
      ),
    );
  }

  QueryResponse build() {
    final primaryResultSet = _resultSets.isNotEmpty
        ? _resultSets.first
        : const QueryResultSet(index: 0, rows: [], rowCount: 0);

    return QueryResponse(
      id: _uuid.v4(),
      requestId: _request.id,
      agentId: _request.agentId,
      data: primaryResultSet.rows,
      affectedRows: _totalAffectedRows > 0 ? _totalAffectedRows : primaryResultSet.rowCount,
      startedAt: _startedAt,
      timestamp: DateTime.now(),
      columnMetadata: primaryResultSet.columnMetadata,
      resultSets: List<QueryResultSet>.from(_resultSets),
      items: List<QueryResponseItem>.from(_items),
    );
  }
}
