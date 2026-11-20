import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/validation/sql_validator.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_paginated_sql_builder.dart';

import '../helpers/e2e_env.dart';
import '../helpers/mock_odbc_connection_settings.dart';

void main() async {
  await E2EEnv.load();
  for (final (type, dsn) in [
    (DatabaseType.sqlServer, E2EEnv.odbcSqlServerConnectionString),
    (DatabaseType.sybaseAnywhere, E2EEnv.odbcConnectionString),
    (DatabaseType.postgresql, E2EEnv.odbcPostgresqlConnectionString),
  ]) {
    test(
      'keyset includes trailing NULL within its ordering group on ${type.name}',
      () async {
        final locator = createAsyncOdbcServiceLocatorForSettings(MockOdbcConnectionSettings());
        addTearDown(locator.shutdown);
        final service = locator.asyncService;
        (await service.initialize()).getOrThrow();
        final conn = (await service.connect(dsn!)).getOrThrow();
        addTearDown(() async => (await service.disconnect(conn.id)).getOrThrow());
        final direction = type == DatabaseType.postgresql ? 'ASC' : 'DESC';
        final sql = '''
SELECT grp, score, id FROM (
  SELECT 0 AS grp, CAST(NULL AS INTEGER) AS score, 1 AS id
  UNION ALL SELECT 1, 10, 2
  UNION ALL SELECT 1, NULL, 3
  UNION ALL SELECT 2, 10, 4
) AS fixture ORDER BY grp, score $direction, id''';
        final order = SqlValidator.validatePaginationQuery(sql).getOrThrow().orderBy;
        final offsetQuery = OdbcPaginatedSqlBuilder.buildOffsetPaginatedSql(
          sql,
          type,
          QueryPaginationRequest(page: 2, pageSize: 2, orderBy: order),
        );
        final offset = (await service.executeQuery(offsetQuery, connectionId: conn.id)).getOrThrow();
        expect(offset.rows.map((row) => row.last), [3, 4]);
        final query = OdbcPaginatedSqlBuilder.buildCursorPaginatedSql(
          sql,
          type,
          QueryPaginationRequest(page: 2, pageSize: 2, orderBy: order, lastRowValues: const [1, 10, 2]),
        );
        final result = (await service.executeQuery(query, connectionId: conn.id)).getOrThrow();
        expect(result.rows.map((row) => row.last), [3, 4]);
      },
      skip: dsn == null,
      tags: ['live'],
    );
  }
}
