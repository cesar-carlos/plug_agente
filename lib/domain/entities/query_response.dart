// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
// Reason: QueryResponse uses ID-based equality for response tracking.

import 'package:plug_agente/domain/entities/query_pagination.dart';

class QueryResultSet {
  const QueryResultSet({
    required this.index,
    required this.rows,
    required this.rowCount,
    this.affectedRows,
    this.columnMetadata,
  });

  final int index;
  final List<Map<String, dynamic>> rows;
  final int rowCount;
  final int? affectedRows;
  final List<Map<String, dynamic>>? columnMetadata;

  QueryResultSet copyWith({
    List<Map<String, dynamic>>? rows,
    int? rowCount,
    int? affectedRows,
    List<Map<String, dynamic>>? columnMetadata,
  }) {
    return QueryResultSet(
      index: index,
      rows: rows ?? this.rows,
      rowCount: rowCount ?? this.rowCount,
      affectedRows: affectedRows ?? this.affectedRows,
      columnMetadata: columnMetadata ?? this.columnMetadata,
    );
  }
}

class QueryResponseItem {
  const QueryResponseItem.resultSet({
    required this.index,
    required this.resultSet,
  }) : rowCount = null;

  const QueryResponseItem.rowCount({
    required this.index,
    required this.rowCount,
  }) : resultSet = null;

  final int index;
  final QueryResultSet? resultSet;
  final int? rowCount;

  bool get isResultSet => resultSet != null;
  bool get isRowCount => rowCount != null;
}

class QueryResponse {
  const QueryResponse({
    required this.id,
    required this.requestId,
    required this.agentId,
    required this.data,
    required this.timestamp,
    this.affectedRows,
    this.error,
    this.columnMetadata,
    this.pagination,
    this.resultSets = const <QueryResultSet>[],
    this.items = const <QueryResponseItem>[],
  });
  final String id;
  final String requestId;
  final String agentId;
  final List<Map<String, dynamic>> data;
  final int? affectedRows;
  final DateTime timestamp;
  final String? error;
  final List<Map<String, dynamic>>? columnMetadata;
  final QueryPaginationInfo? pagination;
  final List<QueryResultSet> resultSets;
  final List<QueryResponseItem> items;

  bool get hasMultiResult =>
      resultSets.length > 1 || items.any((item) => item.isRowCount);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QueryResponse && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
