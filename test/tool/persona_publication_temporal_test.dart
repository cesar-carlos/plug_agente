import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:result_dart/result_dart.dart';
import 'package:test/test.dart';
import '../../tool/homologation/persona_publication_fixture.dart';

class Service extends Mock implements odbc.OdbcService {}

const db = 'se7e_persona_123456abcdef_test';
Map<String, dynamic> declaration({String? storage}) => {
  'table': 'publication_dates',
  'columns': [
    {'name': 'id', 'type': 'integer', 'nullable': false, 'generated': false},
    {
      'name': 'at',
      'type': 'date',
      'nullable': true,
      'generated': false,
      'temporalStorage': ?storage,
    },
  ],
  'primaryKey': ['id'],
  'uniqueKeys': <List<String>>[],
};
void main() {
  late Service service;
  late List<String> statements;
  late List<Map<String, dynamic>> inserts;
  setUp(() {
    service = Service();
    statements = [];
    inserts = [];
    when(() => service.connect(any(), options: any(named: 'options'))).thenAnswer(
      (_) async => Success(odbc.Connection(id: 'fixture', connectionString: '', createdAt: DateTime.utc(2026))),
    );
    when(() => service.disconnect(any())).thenAnswer((_) async => const Success(unit));
    when(() => service.executeQuery(any(), connectionId: any(named: 'connectionId'))).thenAnswer((call) async {
      final sql = call.positionalArguments[0] as String;
      statements.add(sql);
      return Success(
        odbc.QueryResult(
          columns: const ['value'],
          rows: sql == 'SELECT DB_NAME()'
              ? [
                  [db],
                ]
              : sql.startsWith('SELECT COUNT(*)')
              ? [
                  [0],
                ]
              : [],
          rowCount: 0,
        ),
      );
    });
    when(() => service.executeQueryNamed(any(), any(), any())).thenAnswer((call) async {
      inserts.add(Map<String, dynamic>.from(call.positionalArguments[2] as Map));
      return const Success(odbc.QueryResult(columns: [], rows: [], rowCount: 0));
    });
  });
  Future<void> prepare(PublicationFixture fixture, Object? value) => fixture.prepare([
    {
      'table': 'publication_dates',
      'rows': [
        {
          'id': {'type': 'integer', 'value': '1'},
          'at': {'type': value == null ? 'null' : 'date', 'value': value},
        },
      ],
    },
  ]);
  test('preserves final millisecond and next-day boundary with explicit storage', () async {
    final f = PublicationFixture(service, '', db, 'mssql', [declaration(storage: 'datetime2_3')]);
    await f.initialize();
    expect(statements.any((s) => s.contains('[at] DATETIME2(3)')), isTrue);
    for (final value in [
      '2026-11-10T23:59:59.997Z',
      '2026-11-11T00:00:00.000Z',
      '2026-11-10T12:13:14Z',
      '2026-11-10',
    ]) {
      await prepare(f, value);
      expect((inserts.last['at'] as odbc.ParamValueString).value, value.replaceFirst(RegExp(r'Z$'), ''));
    }
    await prepare(f, null);
    expect(inserts.last['at'], isA<odbc.ParamValueNull>());
  });
  test('legacy date stays DATE and refuses timestamp instead of truncating', () async {
    final f = PublicationFixture(service, '', db, 'mssql', [declaration()]);
    await f.initialize();
    expect(statements.any((s) => s.contains('[at] DATE,')), isTrue);
    await prepare(f, '2026-11-10');
    await expectLater(prepare(f, '2026-11-10T23:59:59.997Z'), throwsStateError);
    expect(inserts.length, 1);
  });
  for (final value in [
    '2026-02-30T12:00:00Z',
    '2026-11-10T24:00:00Z',
    '2026-11-10T23:59:59.9971Z',
    '2026-11-10T23:59:59',
    '2026-11-10T23:59:59-04:00',
    "2026-11-10';DROP TABLE x",
    '0000-01-01',
    '2026-02-30',
  ]) {
    test('rejects invalid or inexact temporal value $value without insertion', () async {
      final f = PublicationFixture(service, '', db, 'mssql', [declaration(storage: 'datetime2_3')]);
      await expectLater(prepare(f, value), throwsStateError);
      expect(inserts, isEmpty);
    });
  }
  for (final engine in ['postgres', 'sybase']) {
    test('rejects MSSQL temporal storage on $engine before IO', () {
      expect(
        () => PublicationFixture(service, '', db, engine, [declaration(storage: 'datetime2_3')]),
        throwsStateError,
      );
      verifyZeroInteractions(service);
    });
  }
  test('rejects unknown storage before IO', () {
    expect(() => PublicationFixture(service, '', db, 'mssql', [declaration(storage: 'unknown')]), throwsStateError);
    verifyZeroInteractions(service);
  });
  for (final sameStorage in [false, true]) {
    test('FK requires matching temporal storage: $sameStorage', () {
      final parent = declaration(storage: 'datetime2_3')
        ..['uniqueKeys'] = [
          ['at'],
        ];
      final child = declaration(storage: sameStorage ? 'datetime2_3' : null)
        ..['table'] = 'publication_child'
        ..['foreignKeys'] = [
          {
            'columns': ['at'],
            'targetTable': 'publication_dates',
            'targetColumns': ['at'],
          },
        ];
      if (sameStorage) {
        expect(PublicationFixture(service, '', db, 'mssql', [parent, child]).tables.length, 2);
      } else {
        expect(() => PublicationFixture(service, '', db, 'mssql', [parent, child]), throwsStateError);
      }
      verifyZeroInteractions(service);
    });
    test('audit copy requires matching temporal storage: $sameStorage', () {
      final source = declaration(storage: 'datetime2_3')..['insertAudit'] = {'targetTable': 'publication_audit'};
      final target = declaration(storage: sameStorage ? 'datetime2_3' : null)..['table'] = 'publication_audit';
      if (sameStorage) {
        expect(PublicationFixture(service, '', db, 'mssql', [source, target]).tables.length, 2);
      } else {
        expect(() => PublicationFixture(service, '', db, 'mssql', [source, target]), throwsStateError);
      }
      verifyZeroInteractions(service);
    });
  }
}
