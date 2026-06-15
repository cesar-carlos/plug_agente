import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_result_mapper.dart';

void main() {
  group('OdbcGatewayQueryResultMapper', () {
    test('should return null pagination when request has no pagination', () {
      final info = OdbcGatewayQueryResultMapper.buildPaginationResponse(
        null,
        [
          {'id': 1},
        ],
      );
      expect(info, isNull);
    });

    test('should map rows and column metadata from QueryResult', () {
      const result = QueryResult(
        columns: ['id', 'name'],
        rows: [
          [1, 'a'],
          [2, 'b'],
        ],
        rowCount: 2,
      );

      final maps = OdbcGatewayQueryResultMapper.convertQueryResultToMaps(
        result,
      );
      final meta = OdbcGatewayQueryResultMapper.buildColumnMetadata(
        result,
      );

      expect(maps, [
        {'id': 1, 'name': 'a'},
        {'id': 2, 'name': 'b'},
      ]);
      expect(meta, [
        {'name': 'id'},
        {'name': 'name'},
      ]);
    });

    test('should propagate rich columnsMetadata when present', () {
      const result = QueryResult(
        columns: ['id'],
        rows: [
          [1],
        ],
        rowCount: 1,
        columnsMetadata: [
          ColumnMetadata(name: 'id', odbcType: 2),
        ],
      );

      final meta = OdbcGatewayQueryResultMapper.buildColumnMetadata(result);

      expect(meta, [
        {'name': 'id', 'odbc_type': 2},
      ]);
    });

    test(
      'should set hasNextPage and nextCursor when lookahead row exists',
      () {
        const pagination = QueryPaginationRequest(
          page: 1,
          pageSize: 2,
          queryHash: 'qh',
          orderBy: [
            QueryPaginationOrderTerm(
              expression: 'id',
              lookupKey: 'id',
            ),
          ],
        );
        final rawData = [
          {'id': 1},
          {'id': 2},
          {'id': 3},
        ];

        final info = OdbcGatewayQueryResultMapper.buildPaginationResponse(
          pagination,
          rawData,
        );

        expect(info, isNotNull);
        expect(info!.hasNextPage, isTrue);
        expect(info.returnedRows, 2);
        expect(info.nextCursor, isNotNull);
      },
    );

    test('should emit offset fallback cursor when last ordered row contains null', () {
      const pagination = QueryPaginationRequest(
        page: 1,
        pageSize: 2,
        queryHash: 'qh',
        orderBy: [
          QueryPaginationOrderTerm(
            expression: 'created_at',
            lookupKey: 'created_at',
          ),
        ],
      );
      final rawData = [
        {'created_at': '2026-05-01T00:00:00Z'},
        {'created_at': null},
        {'created_at': '2026-05-03T00:00:00Z'},
      ];

      final info = OdbcGatewayQueryResultMapper.buildPaginationResponse(
        pagination,
        rawData,
      );

      expect(info, isNotNull);
      final decoded = QueryPaginationCursor.fromToken(info!.nextCursor!);
      expect(info.hasNextPage, isTrue);
      expect(decoded.offset, 2);
      expect(decoded.page, 2);
      expect(decoded.isStableCursor, isFalse);
    });
  });
}
