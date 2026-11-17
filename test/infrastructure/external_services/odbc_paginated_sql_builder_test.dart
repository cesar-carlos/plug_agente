import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/validation/sql_validator.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_result_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_paginated_sql_builder.dart';

void main() {
  for (final value in [
    DateTime.utc(2026, 11, 17, 23, 59, 58, 123, 456),
    double.nan,
    double.infinity,
    <int>[1],
  ]) {
    test('non-JSON key ${value.runtimeType} continues from explicit offset without changing rows', () {
      const pagination = QueryPaginationRequest(
        page: 3,
        pageSize: 2,
        offset: 4,
        queryHash: 'synthetic',
        orderBy: [QueryPaginationOrderTerm(expression: 'id', lookupKey: 'id')],
      );
      final rows = [
        {'id': value},
        {'id': value},
        {'id': value},
      ];
      final result = OdbcGatewayQueryResultMapper.materializePagination(pagination, rows);
      final cursor = QueryPaginationCursor.fromToken(result.pagination!.nextCursor!);
      expect(cursor.offset, 6);
      expect(cursor.page, 4);
      expect(cursor.isLegacyOffsetCursor, isTrue);
      expect(identical(result.data.last['id'], value), isTrue);
      final last = OdbcGatewayQueryResultMapper.materializePagination(pagination, [rows.first]);
      expect(last.pagination!.hasNextPage, isFalse);
      expect(last.pagination!.nextCursor, isNull);
    });
  }

  test('temporal sort returns page unchanged and a usable offset continuation', () {
    final date = DateTime(2026, 11, 17, 23, 59, 58, 123, 456);
    final plan = SqlValidator.validatePaginationQuery(
      'SELECT due, id FROM fixture ORDER BY due, id',
    ).getOrThrow();
    final request = QueryPaginationRequest(
      page: 1,
      pageSize: 1,
      queryHash: plan.queryFingerprint,
      orderBy: plan.orderBy,
    );
    final page = OdbcGatewayQueryResultMapper.materializePagination(request, [
      {'due': date, 'id': 7},
      {'due': date.add(const Duration(days: 1)), 'id': 8},
    ]);
    expect(page.data, [
      {'due': date, 'id': 7},
    ]);
    expect(identical(page.data.single['due'], date), isTrue);
    expect(page.pagination!.hasNextPage, isTrue);
    final cursor = QueryPaginationCursor.fromToken(page.pagination!.nextCursor!);
    expect(cursor.isLegacyOffsetCursor, isTrue);
    expect(cursor.offset, 1);
    expect(cursor.page, 2);
    expect(cursor.pageSize, 1);
    final sql = OdbcPaginatedSqlBuilder.buildOffsetPaginatedSql(
      'SELECT due, id FROM fixture ORDER BY due, id',
      DatabaseType.sqlServer,
      QueryPaginationRequest(page: cursor.page, pageSize: cursor.pageSize, offset: cursor.offset),
    );
    expect(sql, contains('OFFSET 1 ROWS'));
    expect(sql, contains('FETCH NEXT 2 ROWS ONLY'));
  });

  group('OdbcPaginatedSqlBuilder', () {
    for (final type in DatabaseType.values) {
      test('qualified sort uses projected alias for $type and cursor lookup', () {
        const original = 'SELECT p.id AS "key", p.amount AS "amount" FROM orders p ORDER BY p.id DESC';
        final plan = SqlValidator.validatePaginationQuery(original).getOrThrow();
        expect(plan.orderBy.single.expression, '"key"');
        expect(plan.orderBy.single.lookupKey, 'key');
        expect(plan.orderBy.single.descending, isTrue);
        final request = QueryPaginationRequest(
          page: 1,
          pageSize: 2,
          queryHash: plan.queryFingerprint,
          orderBy: plan.orderBy,
        );
        final sql = OdbcPaginatedSqlBuilder.buildOffsetPaginatedSql(original, type, request);
        expect(sql, contains('ORDER BY "key" DESC'));
        expect(sql, isNot(contains('ORDER BY p.id')));
        final token = OdbcPaginatedSqlBuilder.buildNextCursorToken(
          pagination: request,
          pageData: const [
            {'key': 7, 'amount': 11},
          ],
        );
        final cursor = QueryPaginationCursor.fromToken(token!);
        expect(cursor.isStableCursor, isTrue);
        expect(cursor.lastRowValues, [7]);
        final cursorSql = OdbcPaginatedSqlBuilder.buildCursorPaginatedSql(
          original,
          type,
          QueryPaginationRequest(
            page: 2,
            pageSize: 2,
            queryHash: plan.queryFingerprint,
            orderBy: plan.orderBy,
            lastRowValues: cursor.lastRowValues,
          ),
        );
        expect(cursorSql, contains('"key" < 7'));
      });
    }
    for (final query in [
      'SELECT p.id AS key FROM orders p ORDER BY p.secret',
      'SELECT p.id AS key, p.amount AS key FROM orders p ORDER BY p.id',
      'SELECT p.id, p.amount + 1 AS amount FROM orders p ORDER BY p.id',
      'SELECT * FROM orders p ORDER BY p.id',
      'WITH q AS (SELECT id FROM orders) SELECT q.id FROM q ORDER BY q.id',
    ]) {
      test('unproven qualified projection is refused: $query', () {
        expect(SqlValidator.validatePaginationQuery(query).isError(), isTrue);
      });
    }
    test('qualified column without explicit alias retains its output name', () {
      final plan = SqlValidator.validatePaginationQuery(
        'SELECT p.id, p.amount FROM orders p ORDER BY p.id',
      ).getOrThrow();
      expect(plan.orderBy.single.expression, 'id');
      expect(plan.orderBy.single.lookupKey, 'id');
    });

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

    test(
      'buildOffsetPaginatedSql sybaseAnywhere nests inner SELECT TOP when present',
      () {
        final sql = OdbcPaginatedSqlBuilder.buildOffsetPaginatedSql(
          'SELECT TOP 1 Nome FROM Cliente ORDER BY CodCliente',
          DatabaseType.sybaseAnywhere,
          const QueryPaginationRequest(
            page: 1,
            pageSize: 50,
            orderBy: [
              QueryPaginationOrderTerm(expression: 'CodCliente', lookupKey: 'CodCliente'),
            ],
          ),
        );
        expect(sql, contains('SELECT TOP 1 Nome FROM Cliente'));
        expect(sql, contains('TOP 51 START AT 1'));
      },
    );

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
