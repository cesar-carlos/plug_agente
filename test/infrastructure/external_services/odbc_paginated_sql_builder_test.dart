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
  });
}
