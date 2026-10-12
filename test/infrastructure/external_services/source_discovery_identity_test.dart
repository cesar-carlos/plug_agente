import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/services/sql_operation_statement_guard.dart';
import 'package:plug_agente/domain/entities/expected_source.dart';
import 'package:plug_agente/domain/entities/source_discovery.dart';
import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_discovery.dart';
import 'package:result_dart/result_dart.dart';
import '../../application/services/sql_operation_executor_test.dart' show fixtureConfig;
import 'odbc_sql_operation_transaction_test.dart' show Native, info;

void main() {
  const uuid = '11111111-1111-4111-8111-111111111111';
  late Native native;
  final sql = OdbcSourceDiscovery.metadataSql('sybase');
  setUp(() {
    native = Native();
    when(() => native.getConnectionDbmsInfo('connection')).thenAnswer((_) async => Success(info('sybase_asa')));
  });
  void metadata(List<List<Object?>> rows) {
    when(() => native.executeQueryNamed('connection', sql, const {})).thenAnswer(
      (_) async => Success(
        odbc.QueryResult(columns: const ['db', 'database_uuid', 'identity_version'], rows: rows, rowCount: rows.length),
      ),
    );
  }

  Future<SourceDiscovery> inspect() =>
      OdbcSourceDiscovery.inspectConnection(native, 'connection', fixtureConfig, 'test_db');
  test('SQL Anywhere hashes the provisioned UUID, never reserved properties or locators', () async {
    metadata([
      ['test_db', uuid, '1'],
    ]);
    final first = await inspect();
    expect(first.identityKind, 'provisioned');
    expect(first.dialect, 'sybase');
    expect((await inspect()).identityHash, first.identityHash);
    metadata([
      ['test_db', '22222222-2222-4222-8222-222222222222', '1'],
    ]);
    expect((await inspect()).identityHash, isNot(first.identityHash));
    expect(sql, contains('"DBA"."se7e_source_identity"'));
    expect(sql, isNot(contains('IdentitySignature')));
    expect(sql, isNot(contains('CREATE')));
  });
  test('missing, duplicate, malformed or unknown-version marker is never enrollment evidence', () async {
    for (final rows in <List<List<Object?>>>[
      [],
      [
        ['test_db', uuid, '1'],
        ['test_db', uuid, '1'],
      ],
      [
        ['test_db', null, '1'],
      ],
      [
        ['test_db', 'a-file-path', '1'],
      ],
      [
        ['test_db', uuid, '2'],
      ],
      [
        ['another_db', uuid, '1'],
      ],
    ]) {
      metadata(rows);
      await expectLater(inspect(), throwsA(anything));
    }
  });
  test('provisioned identity is only valid for SQL Anywhere; locator never matches', () {
    for (final dialect in ['postgres', 'mssql', 'sybase', 'firebird']) {
      final expected = ExpectedSource(dialect: dialect, identityHash: 'a' * 64);
      for (final kind in ['native', 'provisioned', 'locator']) {
        final proof = SourceDiscovery(
          database: 'test_db',
          dialect: dialect,
          identityHash: 'a' * 64,
          identityKind: kind,
          engineVersion: 'test',
        );
        if (kind == (dialect == 'sybase' ? 'provisioned' : 'native')) {
          expect(() => expected.verify(proof), returnsNormally);
        } else {
          expect(() => expected.verify(proof), throwsA(anything));
        }
      }
    }
  });
  test('operation guard rejects technical identity references including quoted names', () {
    for (final table in ['DBA.se7e_source_identity', '"DBA"."se7e_source_identity"', '[DBA].[SE7E_SOURCE_IDENTITY]']) {
      final step = SqlOperationStep(
        id: 'write',
        effect: SqlOperationEffect.update,
        sql: 'UPDATE $table SET version=:v WHERE singleton=:s',
        params: {},
        outputs: {},
        affectedRows: const SqlRowBounds(1, 1),
      );
      expect(() => const SqlOperationStatementGuard().validate(step), throwsA(anything));
    }
  });
}
