import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_schema.dart';

import '../../helpers/source_schema_fixture.dart';

void main() {
  final mismatch = isA<DatabaseFailure>()
      .having((failure) => failure.code, 'code', 'SOURCE_STRUCTURE_MISMATCH')
      .having((failure) => failure.context['retryable'], 'retryable', false);

  for (final dialect in ['postgres', 'mssql', 'sybase']) {
    test('validates wide reordered columns for $dialect without extra catalog calls', () async {
      final fixture = SourceSchemaFixture(1024);
      fixture.columnRows = fixture.columnRows.reversed.toList();
      await fixture.validate(dialect: dialect);
      expect(fixture.catalogCalls, 2);
    });
  }
  test('refuses duplicate expected column even when both definitions match', () async {
    final fixture = SourceSchemaFixture(2);
    fixture.columnRows.add([...fixture.columnRows.first]);
    await expectLater(fixture.validate(), throwsA(mismatch));
  });
  test('ignores same column name in another resource and unused duplicates', () async {
    final fixture = SourceSchemaFixture(1);
    fixture.columnRows.add(['other', 'fixture', 'column_0', 'text', 1, 0, 0]);
    fixture.columnRows.addAll([
      ['public', 'fixture', 'unused', 'int4', 0, 10, 0],
      ['public', 'fixture', 'unused', 'int4', 0, 10, 0],
    ]);
    await fixture.validate();
  });
  test('does not reuse catalog evidence between verifications', () async {
    final fixture = SourceSchemaFixture(1);
    await fixture.validate();
    fixture.columnRows.clear();
    await expectLater(fixture.validate(), throwsA(mismatch));
    expect(fixture.catalogCalls, 4);
  });
  test('preserves catalog whitespace and native type normalization', () async {
    final fixture = SourceSchemaFixture(1);
    fixture.columnRows.first[2] = ' column_0 ';
    fixture.columnRows.first[3] = ' INT4 ';
    await fixture.validate();
  });
  test('refuses duplicate column after catalog name normalization', () async {
    final fixture = SourceSchemaFixture(1);
    fixture.columnRows.add(['public', 'fixture', ' column_0 ', 'int4', 0, 10, 0]);
    await expectLater(fixture.validate(), throwsA(mismatch));
  });
  for (final change in <int, Object?>{2: 'COLUMN_0', 3: 'text', 4: null, 5: 11, 6: 1}.entries) {
    test('rejects changed column field ${change.key}', () async {
      final fixture = SourceSchemaFixture(1);
      fixture.columnRows.first[change.key] = change.value;
      await expectLater(fixture.validate(), throwsA(mismatch));
    });
  }

  for (final nativeType in ['varchar', 'nvarchar', 'varbinary']) {
    test('MAX $nativeType maps to nullable size and preserves structure verification', () async {
      final fixture = SourceSchemaFixture(1);
      fixture.columnRows.first[3] = nativeType;
      fixture.columnRows.first[5] = -1;
      fixture.expected.resources.first.columns.first['nativeType'] = nativeType;
      fixture.expected.resources.first.columns.first['size'] = null;
      expect(OdbcSourceSchema.columnSize({'TYPE_NAME': nativeType, 'COLUMN_SIZE': -1}, 'mssql'), isNull);
      await fixture.validate(dialect: 'mssql');
      fixture.columnRows.first[5] = 100;
      await expectLater(fixture.validate(dialect: 'mssql'), throwsA(mismatch));
    });
  }
  test('MAX normalization does not conceal other negative metadata or change zero', () {
    expect(OdbcSourceSchema.columnSize({'TYPE_NAME': 'varchar', 'COLUMN_SIZE': -2}, 'mssql'), -2);
    expect(OdbcSourceSchema.columnSize({'TYPE_NAME': 'varchar', 'COLUMN_SIZE': -1}, 'postgres'), -1);
    expect(OdbcSourceSchema.columnSize({'TYPE_NAME': 'int', 'COLUMN_SIZE': -1}, 'mssql'), -1);
    expect(OdbcSourceSchema.columnSize({'TYPE_NAME': 'nvarchar', 'COLUMN_SIZE': 0}, 'mssql'), 0);
  });

  const key = <String, Object?>{
    'name': 'fk',
    'status': 'enabled',
    'columns': ['a', 'b'],
    'targetColumns': ['x', 'y'],
    'target': {'schema': 'public', 'name': 'parent', 'type': 'table'},
  };
  test('matches equivalent independently allocated composite constraints', () {
    expect(
      OdbcSourceSchema.sameKey(key, {
        ...key,
        'columns': ['a', 'b'],
        'targetColumns': ['x', 'y'],
        'target': {'type': 'table', 'name': 'parent', 'schema': 'public'},
      }, 'postgres'),
      isTrue,
    );
  });
  for (final change in <String, Object?>{
    'name': 'other',
    'status': 'disabled',
    'columns': ['b', 'a'],
    'targetColumns': ['x'],
    'target': {'schema': 'other', 'name': 'parent', 'type': 'table'},
  }.entries) {
    test('rejects changed constraint ${change.key}', () {
      expect(OdbcSourceSchema.sameKey(key, {...key, change.key: change.value}, 'postgres'), isFalse);
    });
  }
  test('keeps absent target columns distinct from an empty list', () {
    final primary = {...key}
      ..remove('targetColumns')
      ..remove('target');
    expect(OdbcSourceSchema.sameKey(primary, Map.of(primary), 'postgres'), isTrue);
    expect(OdbcSourceSchema.sameKey(primary, {...primary, 'targetColumns': <String>[]}, 'postgres'), isFalse);
  });
}
