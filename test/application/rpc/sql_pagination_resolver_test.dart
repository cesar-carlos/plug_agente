import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_pagination_resolver.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';

void main() {
  const negotiatedExtensions = <String, dynamic>{};

  group('resolvePagination', () {
    for (final options in <Object>[
      [],
      {'page': 0, 'page_size': 0},
      {'page': -1},
      {'cursor': 42},
      {'page': 9223372036854775807, 'page_size': 10},
      {'cursor': const QueryPaginationCursor(page: 9223372036854775807, pageSize: 10).toToken()},
    ]) {
      test('rejects invalid pagination options $options before SQL dispatch', () {
        final result = resolvePagination(
          {'options': options},
          'SELECT id FROM users ORDER BY id',
          100,
          {
            'paginationModes': ['page-offset', 'cursor-keyset'],
          },
        );
        expect(result.hasError, isTrue);
        expect(result.pagination, isNull);
      });
    }
    test('accepts the largest safe computed offset and rejects the next page', () {
      const maxInteger = 0x7fffffffffffffff;
      const size = 10;
      const page = (maxInteger - size - 1) ~/ size + 1;
      expect(QueryPaginationRequest.hasValidBounds(page, size), isTrue);
      expect(QueryPaginationRequest.hasValidBounds(page + 1, size), isFalse);
      const request = QueryPaginationRequest(page: page, pageSize: size);
      expect(request.offset, greaterThanOrEqualTo(0));
      expect(request.offset + request.fetchSizeWithLookAhead, lessThanOrEqualTo(maxInteger));
      expect(QueryPaginationRequest.hasValidBounds(1, size, offset: maxInteger), isFalse);
    });
    test('retains legacy offset and complete stable cursor decoding', () {
      for (final cursor in [
        const QueryPaginationCursor(page: 2, pageSize: 10, offset: 10),
        const QueryPaginationCursor(
          page: 2,
          pageSize: 10,
          queryHash: 'fingerprint',
          orderBy: [QueryPaginationOrderTerm(expression: 'id', lookupKey: 'id')],
          lastRowValues: [10],
        ),
      ]) {
        final decoded = QueryPaginationCursor.fromToken(cursor.toToken());
        expect(decoded.toToken(), cursor.toToken());
      }
    });
    for (final payload in <Object>[
      [],
      {'page': '1', 'page_size': 10},
      {'page': 0, 'page_size': 10},
      {'page': 1, 'page_size': 0},
      {'page': 1, 'page_size': 10, 'offset': -1},
      {'v': 3, 'page': 1, 'page_size': 10},
      {'v': 2, 'page': 1, 'page_size': 10, 'query_hash': 'other-query'},
    ]) {
      test('rejects malformed cursor $payload without throwing', () {
        final token = base64Url.encode(utf8.encode(jsonEncode(payload)));
        final resolution = resolvePagination(
          {
            'options': {'cursor': token},
          },
          'SELECT id FROM users ORDER BY id',
          100,
          {
            'paginationModes': ['cursor-keyset'],
          },
        );
        expect(resolution.hasError, isTrue);
        expect(resolution.pagination, isNull);
      });
    }
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
