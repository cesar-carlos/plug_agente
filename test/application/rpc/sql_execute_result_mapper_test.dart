import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_execute_result_mapper.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';

void main() {
  const mapper = SqlExecuteResultMapper();

  group('SqlExecuteResultMapper.executionTimestampUtcIso', () {
    test('formats local timestamps as UTC ISO-8601', () {
      final local = DateTime(2024, 6, 10, 15, 30, 45);
      expect(
        SqlExecuteResultMapper.executionTimestampUtcIso(local),
        local.toUtc().toIso8601String(),
      );
    });
  });

  group('buildExecuteResultData', () {
    final startedAt = DateTime.utc(2024, 1, 2, 3, 4, 5);
    final finishedAt = DateTime.utc(2024, 1, 2, 3, 4, 6);

    test('maps single-result materialized payload', () {
      final response = QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [
          {'id': 1},
        ],
        timestamp: finishedAt,
        affectedRows: 1,
        columnMetadata: [
          {'name': 'id'},
        ],
      );

      final result = mapper.buildExecuteResultData(
        response,
        startedAt: startedAt,
        finishedAt: finishedAt,
        limitedRows: response.data,
        wasTruncated: false,
        sqlHandlingMode: SqlHandlingMode.managed,
        effectiveMaxRows: 100,
      );

      expect(result['execution_id'], 'exec-1');
      expect(result['started_at'], startedAt.toIso8601String());
      expect(result['finished_at'], finishedAt.toIso8601String());
      expect(result['sql_handling_mode'], 'managed');
      expect(result['max_rows_handling'], 'response_truncation');
      expect(result['effective_max_rows'], 100);
      expect(result['rows'], response.data);
      expect(result['row_count'], 1);
      expect(result['affected_rows'], 1);
      expect(result['column_metadata'], response.columnMetadata);
      expect(result.containsKey('multi_result'), isFalse);
      expect(result.containsKey('truncated'), isFalse);
    });

    test('includes truncated flag and pagination when present', () {
      const pagination = QueryPaginationInfo(
        page: 1,
        pageSize: 10,
        returnedRows: 1,
        hasNextPage: false,
        hasPreviousPage: false,
      );
      final response = QueryResponse(
        id: 'exec-2',
        requestId: 'req-2',
        agentId: 'agent-1',
        data: const [
          {'id': 1},
        ],
        timestamp: finishedAt,
        pagination: pagination,
      );

      final result = mapper.buildExecuteResultData(
        response,
        startedAt: startedAt,
        finishedAt: finishedAt,
        limitedRows: response.data,
        wasTruncated: true,
        sqlHandlingMode: SqlHandlingMode.preserve,
        effectiveMaxRows: 1,
      );

      expect(result['truncated'], isTrue);
      expect(result['sql_handling_mode'], 'preserve');
      expect(result['pagination'], {
        'page': 1,
        'page_size': 10,
        'returned_rows': 1,
        'has_next_page': false,
        'has_previous_page': false,
      });
    });

    test('includes multi-result envelope when response has multiple sets', () {
      const rs0 = QueryResultSet(
        index: 0,
        rows: [
          {'a': 1},
        ],
        rowCount: 1,
      );
      const rs1 = QueryResultSet(
        index: 1,
        rows: [
          {'b': 2},
        ],
        rowCount: 1,
      );
      final response = QueryResponse(
        id: 'exec-3',
        requestId: 'req-3',
        agentId: 'agent-1',
        data: rs0.rows,
        timestamp: finishedAt,
        resultSets: const [rs0, rs1],
        items: const [
          QueryResponseItem.resultSet(index: 0, resultSet: rs0),
          QueryResponseItem.rowCount(index: 1, rowCount: 5),
        ],
      );

      final result = mapper.buildExecuteResultData(
        response,
        startedAt: startedAt,
        finishedAt: finishedAt,
        limitedRows: rs0.rows,
        wasTruncated: false,
        sqlHandlingMode: SqlHandlingMode.managed,
        effectiveMaxRows: 100,
      );

      expect(result['multi_result'], isTrue);
      expect(result['result_set_count'], 2);
      expect(result['item_count'], 2);
      expect(result['result_sets'], hasLength(2));
      expect(result['items'], hasLength(2));
    });

    test('forces multi-result envelope when requested even with empty sets', () {
      final response = QueryResponse(
        id: 'exec-4',
        requestId: 'req-4',
        agentId: 'agent-1',
        data: const <Map<String, dynamic>>[],
        timestamp: finishedAt,
      );

      final result = mapper.buildExecuteResultData(
        response,
        startedAt: startedAt,
        finishedAt: finishedAt,
        limitedRows: const [],
        wasTruncated: false,
        sqlHandlingMode: SqlHandlingMode.managed,
        effectiveMaxRows: 100,
        forceMultiResultEnvelope: true,
      );

      expect(result['multi_result'], isTrue);
      expect(result['result_set_count'], 0);
      expect(result['item_count'], 0);
      expect(result['result_sets'], isEmpty);
      expect(result['items'], isEmpty);
    });
  });

  group('buildResultSetPayload', () {
    test('includes index by default', () {
      const resultSet = QueryResultSet(
        index: 2,
        rows: [
          {'x': 1},
        ],
        rowCount: 1,
        affectedRows: 4,
        columnMetadata: [
          {'name': 'x'},
        ],
      );

      expect(
        mapper.buildResultSetPayload(resultSet),
        {
          'index': 2,
          'rows': resultSet.rows,
          'row_count': 1,
          'column_metadata': resultSet.columnMetadata,
          'affected_rows': 4,
        },
      );
    });

    test('omits index when includeIndex is false', () {
      const resultSet = QueryResultSet(
        index: 0,
        rows: [],
        rowCount: 0,
      );

      final payload = mapper.buildResultSetPayload(resultSet, includeIndex: false);
      expect(payload.containsKey('index'), isFalse);
      expect(payload['rows'], isEmpty);
    });
  });

  group('buildResponseItemPayload', () {
    test('maps result_set items', () {
      const resultSet = QueryResultSet(
        index: 1,
        rows: [
          {'v': 9},
        ],
        rowCount: 1,
      );

      expect(
        mapper.buildResponseItemPayload(
          const QueryResponseItem.resultSet(index: 3, resultSet: resultSet),
        ),
        {
          'type': 'result_set',
          'index': 3,
          'result_set_index': 1,
          'rows': resultSet.rows,
          'row_count': 1,
        },
      );
    });

    test('maps row_count items', () {
      expect(
        mapper.buildResponseItemPayload(
          const QueryResponseItem.rowCount(index: 2, rowCount: 7),
        ),
        {
          'type': 'row_count',
          'index': 2,
          'affected_rows': 7,
        },
      );
    });
  });

  group('applyMaxRowsToMultiResultSets', () {
    test('returns response unchanged when result sets are empty', () {
      final response = QueryResponse(
        id: 'exec-5',
        requestId: 'req-5',
        agentId: 'agent-1',
        data: const [
          {'id': 1},
        ],
        timestamp: DateTime.utc(2024),
      );

      expect(
        mapper.applyMaxRowsToMultiResultSets(response, 1),
        same(response),
      );
    });

    test('returns same instance when no result set exceeds maxRows', () {
      const rs0 = QueryResultSet(
        index: 0,
        rows: [
          {'a': 0},
        ],
        rowCount: 1,
      );
      const rs1 = QueryResultSet(
        index: 1,
        rows: [
          {'b': 0},
        ],
        rowCount: 1,
      );
      final response = QueryResponse(
        id: 'exec-6b',
        requestId: 'req-6b',
        agentId: 'agent-1',
        data: rs0.rows,
        timestamp: DateTime.utc(2024),
        resultSets: const [rs0, rs1],
        items: const [
          QueryResponseItem.resultSet(index: 0, resultSet: rs0),
          QueryResponseItem.resultSet(index: 1, resultSet: rs1),
        ],
      );

      expect(
        mapper.applyMaxRowsToMultiResultSets(response, 10),
        same(response),
      );
    });

    test('maps items by result set index without relying on list order', () {
      const rs0 = QueryResultSet(
        index: 10,
        rows: [
          {'a': 0},
          {'a': 1},
        ],
        rowCount: 2,
      );
      const rs1 = QueryResultSet(
        index: 20,
        rows: [
          {'b': 0},
          {'b': 1},
        ],
        rowCount: 2,
      );
      final response = QueryResponse(
        id: 'exec-6c',
        requestId: 'req-6c',
        agentId: 'agent-1',
        data: rs0.rows,
        timestamp: DateTime.utc(2024),
        resultSets: const [rs0, rs1],
        items: const [
          QueryResponseItem.resultSet(index: 1, resultSet: rs1),
          QueryResponseItem.resultSet(index: 0, resultSet: rs0),
        ],
      );

      final truncated = mapper.applyMaxRowsToMultiResultSets(response, 1);

      expect(truncated.items[0].resultSet!.index, 20);
      expect(truncated.items[0].resultSet!.rows, hasLength(1));
      expect(truncated.items[1].resultSet!.index, 10);
      expect(truncated.items[1].resultSet!.rows, hasLength(1));
    });

    test('truncates each result set independently', () {
      const rs0 = QueryResultSet(
        index: 0,
        rows: [
          {'a': 0},
          {'a': 1},
          {'a': 2},
        ],
        rowCount: 3,
      );
      const rs1 = QueryResultSet(
        index: 1,
        rows: [
          {'b': 0},
          {'b': 1},
        ],
        rowCount: 2,
      );
      final response = QueryResponse(
        id: 'exec-6',
        requestId: 'req-6',
        agentId: 'agent-1',
        data: rs0.rows,
        timestamp: DateTime.utc(2024),
        resultSets: const [rs0, rs1],
        items: const [
          QueryResponseItem.resultSet(index: 0, resultSet: rs0),
          QueryResponseItem.resultSet(index: 1, resultSet: rs1),
        ],
      );

      final truncated = mapper.applyMaxRowsToMultiResultSets(response, 1);

      expect(truncated.resultSets[0].rows, hasLength(1));
      expect(truncated.resultSets[1].rows, hasLength(1));
      expect(truncated.data, truncated.resultSets.first.rows);
      expect(truncated.items[0].resultSet!.rows, hasLength(1));
      expect(truncated.items[1].resultSet!.rows, hasLength(1));
    });
  });

  group('multiResultSetsWereTruncated', () {
    test('returns false when row counts are unchanged', () {
      const rs = QueryResultSet(
        index: 0,
        rows: [
          {'a': 1},
        ],
        rowCount: 1,
      );
      final before = QueryResponse(
        id: 'exec-7',
        requestId: 'req-7',
        agentId: 'agent-1',
        data: rs.rows,
        timestamp: DateTime.utc(2024),
        resultSets: const [rs],
      );

      expect(
        mapper.multiResultSetsWereTruncated(before, before),
        isFalse,
      );
    });

    test('returns true when any result set shrinks', () {
      const rsBefore = QueryResultSet(
        index: 0,
        rows: [
          {'a': 1},
          {'a': 2},
        ],
        rowCount: 2,
      );
      const rsAfter = QueryResultSet(
        index: 0,
        rows: [
          {'a': 1},
        ],
        rowCount: 1,
      );
      final before = QueryResponse(
        id: 'exec-8',
        requestId: 'req-8',
        agentId: 'agent-1',
        data: rsBefore.rows,
        timestamp: DateTime.utc(2024),
        resultSets: const [rsBefore],
      );
      final after = QueryResponse(
        id: 'exec-8',
        requestId: 'req-8',
        agentId: 'agent-1',
        data: rsAfter.rows,
        timestamp: DateTime.utc(2024),
        resultSets: const [rsAfter],
      );

      expect(
        mapper.multiResultSetsWereTruncated(before, after),
        isTrue,
      );
    });
  });
}
