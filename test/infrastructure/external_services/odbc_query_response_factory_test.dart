import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_response_factory.dart';

void main() {
  group('OdbcQueryResponseFactory.isDmlQuery', () {
    test('classifies DML statements as true and SELECT/WITH as false', () {
      expect(OdbcQueryResponseFactory.isDmlQuery('INSERT INTO t VALUES (1)'), isTrue);
      expect(OdbcQueryResponseFactory.isDmlQuery('  update t set a = 1'), isTrue);
      expect(OdbcQueryResponseFactory.isDmlQuery('DELETE FROM t'), isTrue);
      expect(OdbcQueryResponseFactory.isDmlQuery('MERGE INTO t USING s ON (1=1)'), isTrue);
      expect(OdbcQueryResponseFactory.isDmlQuery('SELECT * FROM t'), isFalse);
      expect(OdbcQueryResponseFactory.isDmlQuery('WITH cte AS (SELECT 1) SELECT * FROM cte'), isFalse);
    });
  });

  group('OdbcQueryResponseFactory.fromSingleResult', () {
    test('maps rows and columns and leaves affectedRows null for SELECT', () {
      final response = OdbcQueryResponseFactory.fromSingleResult(
        _request('SELECT id, name FROM users'),
        const QueryResult(
          columns: ['id', 'name'],
          rows: [
            [1, 'a'],
            [2, 'b'],
          ],
          rowCount: 2,
        ),
        startedAt: DateTime(2024, 2, 3),
      );

      expect(response.data, [
        {'id': 1, 'name': 'a'},
        {'id': 2, 'name': 'b'},
      ]);
      expect(response.affectedRows, isNull);
      expect(response.startedAt, DateTime(2024, 2, 3));
      expect(response.columnMetadata?.map((c) => c['name']).toList(), ['id', 'name']);
    });

    test('reports affectedRows from rowCount for DML', () {
      final response = OdbcQueryResponseFactory.fromSingleResult(
        _request('UPDATE users SET name = ?'),
        const QueryResult(columns: [], rows: [], rowCount: 7),
      );

      expect(response.affectedRows, 7);
      expect(response.data, isEmpty);
    });
  });

  group('OdbcQueryResponseFactory.fromMultiResult', () {
    test('aggregates result sets and sums row-count items', () {
      final response = OdbcQueryResponseFactory.fromMultiResult(
        _request('EXEC do_things'),
        const QueryResultMulti(
          items: [
            QueryResultMultiItem.resultSet(
              QueryResult(
                columns: ['v'],
                rows: [
                  [10],
                ],
                rowCount: 1,
              ),
            ),
            QueryResultMultiItem.rowCount(3),
            QueryResultMultiItem.rowCount(4),
          ],
        ),
      );

      expect(response.resultSets.length, 1);
      expect(response.data, [
        {'v': 10},
      ]);
      // Sum of row-count items (3 + 4) takes precedence when present.
      expect(response.affectedRows, 7);
      expect(response.items.length, 3);
    });

    test('falls back to empty primary result set when there are no items', () {
      final response = OdbcQueryResponseFactory.fromMultiResult(
        _request('EXEC noop'),
        const QueryResultMulti(items: []),
      );

      expect(response.data, isEmpty);
      expect(response.resultSets, isEmpty);
      expect(response.affectedRows, 0);
    });
  });
}

QueryRequest _request(String sql) {
  return QueryRequest(
    id: 'req-test',
    agentId: 'agent-test',
    query: sql,
    timestamp: DateTime(2024, 2, 3),
  );
}
