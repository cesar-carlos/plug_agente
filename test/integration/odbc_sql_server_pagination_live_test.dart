import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/validation/sql_validator.dart';

import '../helpers/e2e_env.dart';
import '../helpers/odbc_e2e_coverage_sql.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';

void main() async {
  await E2EEnv.load();
  final dsn = E2EEnv.odbcSqlServerConnectionString;
  final values = List.generate(31, (index) => '(${index + 1})').join(',');
  test(
    'SQL Server pages a direct supplier lookup with named parameters and a date sort',
    () async {
      final h = (await OdbcE2eRpcHarness.open(dsn!, OdbcE2eSqlDialect.sqlServer))!;
      addTearDown(h.shutdown);
      final sql =
          '''
SELECT t.TitleId AS title, s.Name AS supplier, t.DueDate AS due, t.Balance AS balance
FROM (
  SELECT n.id AS TitleId, 7 AS SupplierId, CAST('2026-11-20' AS date) AS DueDate,
         CAST(10.50 AS decimal(12,2)) AS Balance
  FROM (VALUES $values) n(id)
) t
LEFT JOIN (VALUES (7, 'Fixture')) s(SupplierId, Name) ON s.SupplierId = t.SupplierId
WHERE (:supplier IS NULL OR t.SupplierId = :supplier) AND t.Balance > 0
  AND (:name IS NULL OR s.Name LIKE :name)
  AND (CAST(:start AS date) IS NULL OR t.DueDate >= CAST(:start AS date))
ORDER BY due ASC, title ASC''';
      final plan = SqlValidator.validatePaginationQuery(sql).getOrThrow();
      for (final (supplier, start, page, ids) in [
        (7, null, 1, List.generate(30, (i) => i + 1)),
        (7, null, 2, [31]),
        (8, null, 1, <int>[]),
        (7, '2026-11-21', 1, <int>[]),
      ]) {
        final result = (await h.gateway.executeQuery(
          QueryRequest(
            id: 'supplier-$page',
            agentId: 'e2e-agent',
            query: sql,
            timestamp: DateTime.now(),
            parameters: {'supplier': supplier, 'name': null, 'start': start},
            pagination: QueryPaginationRequest(
              page: page,
              pageSize: 30,
              queryHash: plan.queryFingerprint,
              orderBy: plan.orderBy,
            ),
          ),
          timeout: const Duration(seconds: 5),
        )).getOrThrow();
        expect(result.data.map((row) => row['title']), ids);
        expect(result.pagination!.hasNextPage, ids.length == 30);
      }
    },
    skip: dsn == null,
    tags: ['live'],
  );
  for (final sql in [
    'SELECT id AS [page.id] FROM (VALUES $values) v(id) ORDER /*sort*/ BY [page.id]',
    'WITH q AS (SELECT id FROM (VALUES $values) v(id)) SELECT id AS [page.id] FROM q ORDER\nBY [page.id]',
  ]) {
    test(
      'SQL Server returns exact 30+1 rows with dotted alias, CTE=${sql.startsWith('WITH')}',
      () async {
        final h = (await OdbcE2eRpcHarness.open(dsn!, OdbcE2eSqlDialect.sqlServer))!;
        addTearDown(h.shutdown);
        final plan = SqlValidator.validatePaginationQuery(sql).getOrThrow();
        Future<QueryResponse> page(QueryPaginationRequest pagination) async => (await h.gateway.executeQuery(
          QueryRequest(
            id: 'page-${pagination.page}',
            agentId: 'e2e-agent',
            query: sql,
            timestamp: DateTime.now(),
            pagination: pagination,
          ),
          timeout: const Duration(seconds: 5),
        )).getOrThrow();
        final first = await page(
          QueryPaginationRequest(page: 1, pageSize: 30, queryHash: plan.queryFingerprint, orderBy: plan.orderBy),
        );
        expect(first.data.map((row) => row['page.id']), List.generate(30, (i) => i + 1));
        final token = first.pagination!.nextCursor!;
        final cursor = QueryPaginationCursor.fromToken(token);
        expect(cursor.lastRowValues, [30]);
        final last = await page(
          QueryPaginationRequest(
            page: cursor.page,
            pageSize: cursor.pageSize,
            cursor: token,
            queryHash: plan.queryFingerprint,
            orderBy: plan.orderBy,
            lastRowValues: cursor.lastRowValues,
          ),
        );
        expect(last.data.single['page.id'], 31);
        expect(last.pagination!.nextCursor, isNull);
      },
      skip: dsn == null,
      tags: ['live'],
    );
  }
}
