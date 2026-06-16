import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_pagination_resolver.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';

void main() {
  const negotiatedExtensions = <String, dynamic>{};

  group('resolvePagination', () {
    test('returns empty resolution when pagination options are absent', () {
      final resolution = resolvePagination(
        const {},
        'SELECT * FROM users',
        100,
        negotiatedExtensions,
      );
      expect(resolution.hasError, isFalse);
      expect(resolution.pagination, isNull);
    });

    test('resolves page-offset pagination with order by', () {
      final resolution = resolvePagination(
        {
          'options': {'page': 2, 'page_size': 25},
        },
        'SELECT * FROM users ORDER BY id',
        100,
        negotiatedExtensions,
      );
      expect(resolution.hasError, isFalse);
      expect(resolution.pagination, isNotNull);
      expect(resolution.pagination!.page, 2);
      expect(resolution.pagination!.pageSize, 25);
    });

    test('allows offset pagination without explicit order by', () {
      final resolution = resolvePagination(
        {
          'options': {'page': 1, 'page_size': 25},
        },
        'SELECT * FROM users',
        100,
        negotiatedExtensions,
      );
      expect(resolution.hasError, isFalse);
      expect(resolution.pagination, isNotNull);
      expect(resolution.pagination!.orderBy, isEmpty);
    });

    test('rejects cursor pagination without explicit order by', () {
      final resolution = resolvePagination(
        {
          'options': {'cursor': 'YWJj'},
        },
        'SELECT * FROM users',
        100,
        negotiatedExtensions,
      );
      expect(resolution.hasError, isTrue);
      expect(
        resolution.errorMessage,
        'Paginated queries must declare an explicit ORDER BY clause',
      );
    });

    test('rejects page-offset when not negotiated', () {
      final resolution = resolvePagination(
        {
          'options': {'page': 1, 'page_size': 25},
        },
        'SELECT * FROM users ORDER BY id',
        100,
        {
          'paginationModes': ['cursor-keyset'],
        },
      );
      expect(resolution.hasError, isTrue);
      expect(
        resolution.errorMessage,
        'Negotiated protocol does not allow page-offset pagination',
      );
    });

    test('rejects page_size when SQL declares SELECT TOP', () {
      final resolution = resolvePagination(
        {
          'options': {'page': 1, 'page_size': 25},
        },
        'SELECT TOP 10 Nome FROM Cliente ORDER BY CodCliente',
        100,
        negotiatedExtensions,
      );
      expect(resolution.hasError, isTrue);
      expect(
        resolution.errorMessage,
        'Paginated requests cannot include TOP/LIMIT/OFFSET/FETCH in SQL; '
        'use options.page/page_size or options.cursor',
      );
    });

    test('rejects page_size when WITH query declares SELECT TOP', () {
      final resolution = resolvePagination(
        {
          'options': {'page': 1, 'page_size': 25},
        },
        'WITH cte AS (SELECT CodCliente FROM Cliente) '
        'SELECT TOP 1 Nome FROM cte ORDER BY CodCliente',
        100,
        negotiatedExtensions,
      );
      expect(resolution.hasError, isTrue);
      expect(
        resolution.errorMessage,
        'Paginated requests cannot include TOP/LIMIT/OFFSET/FETCH in SQL; '
        'use options.page/page_size or options.cursor',
      );
    });
  });

  group('buildPaginationResult', () {
    test('maps pagination info to wire map', () {
      const info = QueryPaginationInfo(
        page: 2,
        pageSize: 25,
        returnedRows: 10,
        hasNextPage: true,
        hasPreviousPage: true,
        nextCursor: 'cursor-token',
      );

      expect(
        buildPaginationResult(info),
        {
          'page': 2,
          'page_size': 25,
          'returned_rows': 10,
          'has_next_page': true,
          'has_previous_page': true,
          'next_cursor': 'cursor-token',
        },
      );
    });
  });

  group('orderByMatchesPlan', () {
    test('returns true when order terms match', () {
      const term = QueryPaginationOrderTerm(
        expression: 'id',
        lookupKey: 'id',
      );
      expect(orderByMatchesPlan(const [term], const [term]), isTrue);
    });

    test('returns false when order terms differ', () {
      expect(
        orderByMatchesPlan(
          const [
            QueryPaginationOrderTerm(expression: 'id', lookupKey: 'id'),
          ],
          const [
            QueryPaginationOrderTerm(expression: 'name', lookupKey: 'name'),
          ],
        ),
        isFalse,
      );
    });
  });
}
