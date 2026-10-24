import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
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
        (index) => <String, dynamic>{'Col $index': 'v$index'},
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

    test('should materialize LazyString values in managed mode', () async {
      final service = QueryNormalizerService(QueryNormalizer());
      final lazy = LazyString(Uint8List.fromList(utf8.encode('Cliente A')));
      final response = QueryResponse(
        id: 'r1',
        requestId: 'req',
        agentId: 'agent',
        data: <Map<String, dynamic>>[
          <String, dynamic>{'Nome': lazy},
        ],
        timestamp: DateTime.utc(2026),
      );

      final normalized = await service.normalizeAsync(response);

      expect(normalized.data.first['nome'], 'Cliente A');
    });

    test('should materialize LazyString values in preserve mode without renaming columns', () async {
      final service = QueryNormalizerService(QueryNormalizer());
      final lazy = LazyString(Uint8List.fromList(utf8.encode('Cliente A')));
      final response = QueryResponse(
        id: 'r1',
        requestId: 'req',
        agentId: 'agent',
        data: <Map<String, dynamic>>[
          <String, dynamic>{'Nome': lazy},
        ],
        timestamp: DateTime.utc(2026),
      );

      final normalized = await service.normalizeAsync(
        response,
        sqlHandlingMode: SqlHandlingMode.preserve,
      );

      expect(normalized.data.first.containsKey('Nome'), isTrue);
      expect(normalized.data.first['Nome'], 'Cliente A');
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

    test('should keep a preserve response when every cell is already plain', () async {
      final service = QueryNormalizerService(QueryNormalizer());
      final response = QueryResponse(
        id: 'r1',
        requestId: 'req',
        agentId: 'agent',
        data: List<Map<String, dynamic>>.generate(
          QueryNormalizerService.normalizeIsolateRowThreshold,
          (index) => <String, dynamic>{'id': index, 'name': 'ana'},
        ),
        timestamp: DateTime.utc(2026),
      );

      final normalized = await service.normalizeAsync(
        response,
        sqlHandlingMode: SqlHandlingMode.preserve,
      );

      expect(identical(normalized, response), isTrue);
    });

    test('should reuse an unchanged preserve row when a sibling cell is materialized', () async {
      final service = QueryNormalizerService(QueryNormalizer());
      final plain = <String, dynamic>{'id': 1, 'name': 'ana'};
      final stamped = <String, dynamic>{'when': DateTime.utc(2026, 1, 2, 3, 4, 5)};
      final response = QueryResponse(
        id: 'r1',
        requestId: 'req',
        agentId: 'agent',
        data: <Map<String, dynamic>>[plain, stamped],
        timestamp: DateTime.utc(2026),
      );

      final normalized = await service.normalizeAsync(
        response,
        sqlHandlingMode: SqlHandlingMode.preserve,
      );

      expect(identical(normalized.data[0], plain), isTrue);
      expect(normalized.data[1]['when'], '2026-01-02T03:04:05.000Z');
      expect(identical(normalized.data[1], stamped), isFalse);
    });

    test('should materialize a wide preserve result that contains a timestamp', () async {
      final service = QueryNormalizerService(QueryNormalizer());
      final rows = List<Map<String, dynamic>>.generate(
        QueryNormalizerService.normalizeIsolateRowThreshold,
        (index) => <String, dynamic>{'id': index},
      );
      rows[0] = <String, dynamic>{'when': DateTime.utc(2026, 1, 2)};
      final response = QueryResponse(
        id: 'r1',
        requestId: 'req',
        agentId: 'agent',
        data: rows,
        timestamp: DateTime.utc(2026),
      );

      final normalized = await service.normalizeAsync(
        response,
        sqlHandlingMode: SqlHandlingMode.preserve,
      );

      expect(normalized.data.first['when'], '2026-01-02T00:00:00.000Z');
    });

    test('should reuse a wire-safe row when a later managed row still needs rewrite', () async {
      final service = QueryNormalizerService(QueryNormalizer());
      final rows = List<Map<String, dynamic>>.generate(
        QueryNormalizerService.skipRowRewriteRowThreshold,
        (index) => <String, dynamic>{'col_a': 'ana$index'},
      );
      final clean = rows.first;
      rows[rows.length - 1] = <String, dynamic>{'col_b': ' value '};
      final response = QueryResponse(
        id: 'r1',
        requestId: 'req',
        agentId: 'agent',
        data: rows,
        timestamp: DateTime.utc(2026),
      );

      final normalized = await service.normalizeAsync(response);

      expect(identical(normalized.data.first, clean), isTrue);
      expect(normalized.data.last['col_b'], 'value');
      expect(identical(normalized.data.last, rows.last), isFalse);
    });

    test('should skip full rewrite when row keys are already wire-safe', () async {
      final service = QueryNormalizerService(QueryNormalizer());
      final rows = List<Map<String, dynamic>>.generate(
        QueryNormalizerService.skipRowRewriteRowThreshold,
        (index) => <String, dynamic>{'col_$index': 'value$index'},
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

    test('should rewrite a later row when a repeated safe key still needs trim', () async {
      final service = QueryNormalizerService(QueryNormalizer());
      final rows = List<Map<String, dynamic>>.generate(
        QueryNormalizerService.skipRowRewriteRowThreshold,
        (index) => <String, dynamic>{'col_a': 'ana'},
      );
      final clean = rows.first;
      rows[rows.length - 1] = <String, dynamic>{'col_a': ' ana '};
      final response = QueryResponse(
        id: 'r1',
        requestId: 'req',
        agentId: 'agent',
        data: rows,
        timestamp: DateTime.utc(2026),
      );

      final normalized = await service.normalizeAsync(response);

      expect(identical(normalized, response), isFalse);
      expect(identical(normalized.data.first, clean), isTrue);
      expect(normalized.data.last['col_a'], 'ana');
    });

    test('should rewrite a later row when it introduces an unsafe key', () async {
      final service = QueryNormalizerService(QueryNormalizer());
      final rows = List<Map<String, dynamic>>.generate(
        QueryNormalizerService.skipRowRewriteRowThreshold,
        (index) => <String, dynamic>{'col_a': 'ana'},
      );
      final clean = rows.first;
      rows[rows.length - 1] = <String, dynamic>{'Col A': 'ana'};
      final response = QueryResponse(
        id: 'r1',
        requestId: 'req',
        agentId: 'agent',
        data: rows,
        timestamp: DateTime.utc(2026),
      );

      final normalized = await service.normalizeAsync(response);

      expect(identical(normalized, response), isFalse);
      expect(identical(normalized.data.first, clean), isTrue);
      expect(normalized.data.last.keys, ['col_a']);
      expect(normalized.data.last['col_a'], 'ana');
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
