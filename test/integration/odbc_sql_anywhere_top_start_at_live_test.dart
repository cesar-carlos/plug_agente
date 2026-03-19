import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;

import '../helpers/e2e_env.dart';

/// Verifies SQL Anywhere accepts TOP/START AT (agent pagination shape).
void main() async {
  await E2EEnv.load();

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

  group('ODBC SQL Anywhere TOP START AT live', () {
    late odbc.ServiceLocator locator;
    var isReady = false;

    setUpAll(() async {
      if (!dsnValid || !looksLikeSqlAnywhere) {
        return;
      }

      locator = odbc.ServiceLocator()..initialize(useAsync: true);
      final service = locator.asyncService;
      final initResult = await service.initialize();
      if (initResult.isError()) {
        return;
      }
      isReady = true;
    });

    tearDownAll(() {
      if (isReady) {
        locator.shutdown();
      }
    });

    test(
      'should execute TOP START AT pagination-shaped SELECT',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not SQL Anywhere',
        );

        final service = locator.asyncService;
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
      skip: !dsnValid
          ? 'Defina ODBC_TEST_DSN ou ODBC_DSN no .env'
          : !looksLikeSqlAnywhere
          ? 'DSN nao parece SQL Anywhere; use driver SQL Anywhere ou ODBC_SQL_ANYWHERE_TOP_START_AT_QUERY'
          : false,
    );
  });
}
