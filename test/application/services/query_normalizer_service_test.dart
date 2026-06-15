import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';

void main() {
  group('QueryNormalizerService.normalizeAsync', () {
    test('should normalize small result sets on the calling isolate', () async {
      final service = QueryNormalizerService(QueryNormalizer());
      final response = QueryResponse(
        id: 'r1',
        requestId: 'req',
        agentId: 'agent',
        data: <Map<String, dynamic>>[
          <String, dynamic>{'Col Name': ' value '},
        ],
        timestamp: DateTime.utc(2026),
      );

      final normalized = await service.normalizeAsync(response);

      expect(normalized.data.first.containsKey('col_name'), isTrue);
    });

    test('should offload large result sets to a background isolate', () async {
      final service = QueryNormalizerService(QueryNormalizer());
      final rows = List<Map<String, dynamic>>.generate(
        QueryNormalizerService.normalizeIsolateRowThreshold,
        (int index) => <String, dynamic>{'Col $index': 'v$index'},
      );
      final response = QueryResponse(
        id: 'r1',
        requestId: 'req',
        agentId: 'agent',
        data: rows,
        timestamp: DateTime.utc(2026),
      );

      final normalized = await service.normalizeAsync(response);

      expect(normalized.data.length, rows.length);
      expect(normalized.data.first.keys.first, startsWith('col_'));
    });

    test('should skip normalization in preserve mode', () async {
      final service = QueryNormalizerService(QueryNormalizer());
      final response = QueryResponse(
        id: 'r1',
        requestId: 'req',
        agentId: 'agent',
        data: <Map<String, dynamic>>[
          <String, dynamic>{'Col Name': ' value '},
        ],
        timestamp: DateTime.utc(2026),
      );

      final normalized = await service.normalizeAsync(
        response,
        sqlHandlingMode: SqlHandlingMode.preserve,
      );

      expect(normalized.data.first.containsKey('Col Name'), isTrue);
      expect(normalized.data.first['Col Name'], ' value ');
    });

    test('should skip full rewrite when row keys are already wire-safe', () async {
      final service = QueryNormalizerService(QueryNormalizer());
      final rows = List<Map<String, dynamic>>.generate(
        QueryNormalizerService.skipRowRewriteRowThreshold,
        (int index) => <String, dynamic>{'col_$index': 'value$index'},
      );
      final response = QueryResponse(
        id: 'r1',
        requestId: 'req',
        agentId: 'agent',
        data: rows,
        timestamp: DateTime.utc(2026),
      );

      final normalized = await service.normalizeAsync(response);

      expect(identical(normalized, response), isTrue);
    });

    test('should map multi-result items by result set index', () async {
      final service = QueryNormalizerService(QueryNormalizer());
      const rs0 = QueryResultSet(
        index: 10,
        rows: [
          {'Col A': 'one'},
        ],
        rowCount: 1,
      );
      const rs1 = QueryResultSet(
        index: 20,
        rows: [
          {'Col B': 'two'},
        ],
        rowCount: 1,
      );
      final response = QueryResponse(
        id: 'r1',
        requestId: 'req',
        agentId: 'agent',
        data: rs0.rows,
        resultSets: const [rs0, rs1],
        items: const [
          QueryResponseItem.resultSet(index: 1, resultSet: rs1),
          QueryResponseItem.resultSet(index: 0, resultSet: rs0),
        ],
        timestamp: DateTime.utc(2026),
      );

      final normalized = await service.normalizeAsync(response);

      expect(normalized.items[0].resultSet!.rows.first.containsKey('col_b'), isTrue);
      expect(normalized.items[1].resultSet!.rows.first.containsKey('col_a'), isTrue);
    });

    test('should not double count primary rows when resultSets mirror data', () {
      final rows = <Map<String, dynamic>>[
        <String, dynamic>{'Col': 'value'},
      ];
      final response = QueryResponse(
        id: 'r1',
        requestId: 'req',
        agentId: 'agent',
        data: rows,
        resultSets: <QueryResultSet>[
          QueryResultSet(index: 0, rows: rows, rowCount: rows.length),
        ],
        timestamp: DateTime.utc(2026),
      );

      expect(QueryNormalizerService.totalRowCount(response), rows.length);
    });
  });
}
