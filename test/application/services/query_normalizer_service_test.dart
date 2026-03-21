import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/domain/entities/query_response.dart';

void main() {
  late QueryNormalizerService service;

  setUp(() {
    service = QueryNormalizerService(QueryNormalizer());
  });

  group('QueryNormalizerService', () {
    test(
      'should trim string values and lowercase column keys with underscores',
      () {
        final ts = DateTime.utc(2026, 1, 15, 12, 30);
        final response = QueryResponse(
          id: 'r1',
          requestId: 'q1',
          agentId: 'a1',
          data: [
            {
              'User Name': '  alice  ',
              'COUNT(*)': 3,
              'at': ts,
            },
          ],
          timestamp: DateTime.now(),
        );

        final out = service.normalize(response);

        expect(out.data, hasLength(1));
        final row = out.data.single;
        expect(row.keys, containsAll(['user_name', 'count', 'at']));
        expect(row['user_name'], 'alice');
        expect(row['count'], 3);
        expect(row['at'], ts.toIso8601String());
      },
    );

    test('should normalize result sets and keep items aligned', () {
      const rs0 = QueryResultSet(
        index: 0,
        rows: [
          {'A  B': 1},
        ],
        rowCount: 1,
      );
      final response = QueryResponse(
        id: 'r1',
        requestId: 'q1',
        agentId: 'a1',
        data: const <Map<String, dynamic>>[],
        timestamp: DateTime.now(),
        resultSets: const [rs0],
        items: const [
          QueryResponseItem.resultSet(index: 0, resultSet: rs0),
        ],
      );

      final out = service.normalize(response);

      expect(out.resultSets, hasLength(1));
      expect(out.resultSets.single.rows.single.containsKey('a_b'), isTrue);
      expect(out.items.single.resultSet!.rows.single['a_b'], 1);
    });

    test('should pass through rowCount items unchanged', () {
      final response = QueryResponse(
        id: 'r1',
        requestId: 'q1',
        agentId: 'a1',
        data: const <Map<String, dynamic>>[],
        timestamp: DateTime.utc(2026),
        items: const [
          QueryResponseItem.rowCount(index: 0, rowCount: 5),
        ],
      );

      final out = service.normalize(response);

      expect(out.items.single.rowCount, 5);
      expect(out.items.single.resultSet, isNull);
    });
  });
}
