import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_paginated_sql_builder.dart';

void main() {
  group('OdbcPaginatedSqlBuilder', () {
    test('buildOffsetPaginatedSql postgresql includes LIMIT and OFFSET', () {
      final sql = OdbcPaginatedSqlBuilder.buildOffsetPaginatedSql(
        'SELECT id FROM t',
        DatabaseType.postgresql,
        const QueryPaginationRequest(page: 2, pageSize: 10),
      );
      expect(sql, contains('LIMIT 11'));
      expect(sql, contains('OFFSET 10'));
      expect(sql, contains('plug_paginated_source'));
    });

    test('buildOffsetPaginatedSql sybaseAnywhere uses TOP START AT', () {
      final sql = OdbcPaginatedSqlBuilder.buildOffsetPaginatedSql(
        'SELECT id FROM t',
        DatabaseType.sybaseAnywhere,
        const QueryPaginationRequest(page: 1, pageSize: 5),
      );
      expect(sql, contains('TOP 6 START AT 1'));
    });

    test('buildNextCursorToken falls back to offset cursor when order value is null', () {
      const pagination = QueryPaginationRequest(
        page: 2,
        pageSize: 3,
        queryHash: 'qh',
        orderBy: [
          QueryPaginationOrderTerm(
            expression: 'created_at',
            lookupKey: 'created_at',
          ),
        ],
      );

      final token = OdbcPaginatedSqlBuilder.buildNextCursorToken(
        pagination: pagination,
        pageData: const [
          {'created_at': '2026-05-01T00:00:00Z'},
          {'created_at': null},
        ],
      );

      expect(token, isNotNull);
      final decoded = QueryPaginationCursor.fromToken(token!);
      expect(decoded.page, 3);
      expect(decoded.pageSize, 3);
      expect(decoded.offset, 5);
      expect(decoded.isStableCursor, isFalse);
    });

    test('buildOrderByClause accepts dotted/quoted identifiers', () {
      final clause = OdbcPaginatedSqlBuilder.buildOrderByClause(const [
        QueryPaginationOrderTerm(expression: 't.created_at', lookupKey: 'created_at', descending: true),
        QueryPaginationOrderTerm(expression: '[Order Id]', lookupKey: 'Order Id'),
      ]);
      expect(clause, 't.created_at DESC, [Order Id] ASC');
    });

    test('buildOrderByClause rejects unsafe order expression (injection guard)', () {
      expect(
        () => OdbcPaginatedSqlBuilder.buildOrderByClause(const [
          QueryPaginationOrderTerm(
            expression: 'id; DROP TABLE users',
            lookupKey: 'id',
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('buildKeysetWhereClause rejects unsafe order expression (injection guard)', () {
      expect(
        () => OdbcPaginatedSqlBuilder.buildKeysetWhereClause(
          const [
            QueryPaginationOrderTerm(
              expression: '1) OR (1=1',
              lookupKey: 'id',
            ),
          ],
          const [1],
          DatabaseType.postgresql,
        ),
        throwsArgumentError,
      );
    });
  });
}
