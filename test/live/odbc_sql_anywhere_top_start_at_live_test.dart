@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;

import '../helpers/e2e_env.dart';
import '../helpers/live_test_env.dart';
import '../helpers/odbc_live_bootstrap.dart';

/// Verifies SQL Anywhere accepts TOP/START AT (agent pagination shape).
void main() async {
  await loadLiveTestEnv();

  final dsn = E2EEnv.odbcConnectionString;
  final dsnValid = dsn != null && dsn.trim().isNotEmpty;
  final looksLikeSqlAnywhere = dsn?.toLowerCase().contains('anywhere') ?? false;

  final customSql = E2EEnv.odbcSqlAnywhereTopStartAtQuery;
  final sql = (customSql != null && customSql.trim().isNotEmpty)
      ? customSql.trim()
      : '''
SELECT TOP 2 START AT 1 *
FROM (
  SELECT table_id FROM sys.systable ORDER BY table_id
) AS plug_paginated_source
ORDER BY table_id ASC
''';

  final skipTopStartAt = !dsnValid
      ? E2EEnv.skipReasonNoOdbcDsnPrimary
      : (!looksLikeSqlAnywhere
            ? E2EEnv.skipReasonSqlAnywhereDriverMismatch
            : false);

  group('ODBC SQL Anywhere TOP START AT live', () {
    OdbcLiveBootstrap? bootstrap;
    var isReady = false;

    setUpAll(() async {
      if (!dsnValid || !looksLikeSqlAnywhere) {
        return;
      }

      final opened = await OdbcLiveBootstrap.open();
      if (opened == null) {
        return;
      }
      bootstrap = opened;
      isReady = true;
    });

    tearDownAll(() {
      bootstrap?.shutdown();
    });

    test(
      'should execute TOP START AT pagination-shaped SELECT',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not SQL Anywhere',
        );

        final service = bootstrap!.asyncService;
        final connResult = await service.connect(
          dsn!,
          options: const odbc.ConnectionOptions(),
        );
        expect(connResult.isSuccess(), isTrue);
        final connId = connResult.getOrNull()!.id;

        final queryResult = await service.executeQuery(
          sql,
          connectionId: connId,
        );

        expect(queryResult.isSuccess(), isTrue);
        final rows = queryResult.getOrNull()!.rows;
        expect(rows, isNotEmpty);

        await service.disconnect(connId);
      },
      skip: skipTopStartAt,
    );
  });
}
