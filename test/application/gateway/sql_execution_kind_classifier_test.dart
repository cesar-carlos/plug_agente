import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/gateway/sql_execution_kind_classifier.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/entities/query_request.dart';

QueryRequest _request({
  required String query,
  bool expectMultipleResults = false,
}) {
  return QueryRequest(
    id: 'req-1',
    agentId: 'agent-1',
    query: query,
    timestamp: DateTime.utc(2024),
    expectMultipleResults: expectMultipleResults,
  );
}

void main() {
  group('SqlExecutionKindClassifier', () {
    test('classifies short simple SELECT as shortQuery', () {
      final classifier = SqlExecutionKindClassifier();

      expect(
        classifier.classify(_request(query: 'SELECT 1'), null),
        SqlExecutionKind.shortQuery,
      );
    });

    test('classifies join-heavy SQL as longQuery', () {
      final classifier = SqlExecutionKindClassifier();

      expect(
        classifier.classify(
          _request(query: 'SELECT * FROM a JOIN b ON a.id = b.id'),
          null,
        ),
        SqlExecutionKind.longQuery,
      );
    });

    test('classifies multi-result requests as longQuery', () {
      final classifier = SqlExecutionKindClassifier();

      expect(
        classifier.classify(
          _request(query: 'SELECT 1; SELECT 2', expectMultipleResults: true),
          null,
        ),
        SqlExecutionKind.longQuery,
      );
    });

    test('classifies long SQL text as longQuery', () {
      final classifier = SqlExecutionKindClassifier();
      final longSql = 'SELECT ${'x' * 1300}';

      expect(
        classifier.classify(_request(query: longSql), null),
        SqlExecutionKind.longQuery,
      );
    });

    test('classifies high timeout as longQuery', () {
      final classifier = SqlExecutionKindClassifier();

      expect(
        classifier.classify(
          _request(query: 'SELECT 1'),
          const Duration(milliseconds: 16000),
        ),
        SqlExecutionKind.longQuery,
      );
    });

    test('returns cached classification for repeated requests', () {
      final classifier = SqlExecutionKindClassifier(cacheCapacity: 2);
      final request = _request(query: 'SELECT id FROM users WHERE id = 1');

      expect(classifier.classify(request, null), SqlExecutionKind.shortQuery);
      expect(classifier.classify(request, null), SqlExecutionKind.shortQuery);
    });
  });
}
