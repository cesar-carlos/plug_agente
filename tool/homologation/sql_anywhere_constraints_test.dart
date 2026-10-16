import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/infrastructure/external_services/source_schema_sql.dart';
import 'package:uuid/uuid.dart';

// Operator-only SQL in a disposable manifest. Never loads .env or an existing source.
void main() {
  final path = Platform.environment['PERSONA_SQL_FIXTURE_MANIFEST'];
  if (path == null) throw StateError('Explicit disposable manifest is required.');
  final manifest = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final runId = manifest['runId'] as String;
  final root = Directory(manifest['root'] as String).resolveSymbolicLinksSync();
  if (!RegExp(r'^se7e_persona_[a-f0-9]{12}_test$').hasMatch(runId) ||
      Directory(root).parent.resolveSymbolicLinksSync() != Directory.systemTemp.resolveSymbolicLinksSync() ||
      !root.endsWith('${Platform.pathSeparator}$runId')) {
    throw StateError('Only owned temporary fixtures are accepted.');
  }
  final engine = (manifest['engines'] as Map<String, dynamic>)['sybase'] as Map<String, dynamic>;
  late odbc.ServiceLocator locator;
  late odbc.OdbcService service;
  late String id;
  Future<odbc.QueryResult> sql(String query) async =>
      (await service.executeQuery(query, connectionId: id)).getOrThrow();
  Future<List<Object?>> states(String kind, String table, {String Function(String)? transform}) async {
    final statement = SourceSchemaSql.query('sybase', kind);
    final result = (await service.executeQueryNamed(id, transform?.call(statement) ?? statement, {
      'schema': 'DBA',
      'table': table,
    })).getOrThrow();
    expect(result.additionalResults, isEmpty);
    final index = result.columns.indexWhere((c) => c.toLowerCase() == 'constraint_status');
    return result.rows.map((row) => row[index]).toList();
  }

  setUpAll(() async {
    locator = odbc.ServiceLocator()..initialize(useAsync: true, asyncWorkerCount: 2);
    service = locator.syncService;
    (await service.initialize()).getOrThrow();
    final connection = (await service.connect(
      engine['connectionString'] as String,
      options: const odbc.ConnectionOptions(maxReconnectAttempts: 0),
    )).getOrThrow();
    id = connection.id;
    expect((await sql('SELECT DB_NAME()')).rows.single.single, runId);
    await sql(
      'CREATE TABLE constraint_parent (id INTEGER NOT NULL PRIMARY KEY, code INTEGER NOT NULL UNIQUE, nullable_code INTEGER NULL)',
    );
    await sql('CREATE UNIQUE INDEX constraint_nullable ON constraint_parent(nullable_code)');
    await sql(
      'CREATE TABLE constraint_child (id INTEGER NOT NULL PRIMARY KEY, parent_id INTEGER NOT NULL, CONSTRAINT constraint_fk FOREIGN KEY(parent_id) REFERENCES constraint_parent(id))',
    );
  });
  tearDownAll(() async {
    await service.disconnect(id);
    locator.shutdown();
  });
  test('physical declared primary and unique keys and FK are proven on native SQL Anywhere16', () async {
    expect(await states('primary', 'constraint_parent'), ['enabled']);
    // Ordinary nullable unique indexes are not declared UNIQUE constraints.
    expect(await states('unique', 'constraint_parent'), ['enabled']);
    expect(await states('foreign', 'constraint_child'), ['enabled']);
  });
  test('native engine rejects duplicate PK/UNIQUE and orphan FK in isolated data', () async {
    await sql('INSERT INTO constraint_parent(id,code) VALUES(1,10)');
    try {
      expect(
        (await service.executeQuery('INSERT INTO constraint_parent(id,code) VALUES(1,20)', connectionId: id)).isError(),
        isTrue,
      );
      expect(
        (await service.executeQuery('INSERT INTO constraint_parent(id,code) VALUES(2,10)', connectionId: id)).isError(),
        isTrue,
      );
      expect(
        (await service.executeQuery('INSERT INTO constraint_child VALUES(1,999)', connectionId: id)).isError(),
        isTrue,
      );
    } finally {
      await sql('DELETE FROM constraint_child');
      await sql('DELETE FROM constraint_parent');
    }
  });
  test('connection fire_triggers off refuses FK proof without changing its declaration', () async {
    await sql("SET TEMPORARY OPTION fire_triggers='Off'");
    try {
      expect(await states('foreign', 'constraint_child'), ['disabled']);
    } finally {
      await sql("SET TEMPORARY OPTION fire_triggers='On'");
    }
    expect(await states('foreign', 'constraint_child'), ['enabled']);
  });
  test('missing backing index or an unhomologated version stays unknown', () async {
    expect(
      await states(
        'primary',
        'constraint_parent',
        transform: (q) => q.replaceAll('ph.phys_index_id=i.phys_index_id', 'ph.phys_index_id=i.phys_index_id AND 1=0'),
      ),
      ['unknown'],
    );
    expect(await states('foreign', 'constraint_child', transform: (q) => q.replaceAll("LIKE '16.%'", "LIKE '0.%'")), [
      'unknown',
    ]);
    expect(
      await states(
        'foreign',
        'constraint_child',
        transform: (q) =>
            q.replaceAll('pp.phys_index_id=pi.phys_index_id', 'pp.phys_index_id=pi.phys_index_id AND 1=0'),
      ),
      ['unknown'],
    );
  });
  test('server option or unavailable startup evidence cannot enable FK', () async {
    for (final value in ["'-gf'", "'@server-options'", "''"]) {
      expect(
        await states('foreign', 'constraint_child', transform: (q) => q.replaceAll("PROPERTY('CommandLine')", value)),
        [if (value == "'-gf'") 'disabled' else 'unknown'],
      );
    }
    expect(
      await states(
        'foreign',
        'constraint_child',
        transform: (q) => q.replaceAll("PROPERTY('CommandLine')", 'CAST(NULL AS VARCHAR(1024))'),
      ),
      ['unknown'],
    );
    expect(
      await states(
        'foreign',
        'constraint_child',
        transform: (q) => q.replaceAll("CONNECTION_PROPERTY('fire_triggers')", 'CAST(NULL AS VARCHAR(16))'),
      ),
      ['unknown'],
    );
  });
  test('SELECT-only principal can prove scoped native constraints without DDL or option privileges', () async {
    final password = const Uuid().v4().replaceAll('-', '');
    await sql('CREATE USER constraint_reader IDENTIFIED BY "$password"');
    await sql('GRANT SELECT ON DBA.constraint_parent TO constraint_reader');
    await sql('GRANT SELECT ON DBA.constraint_child TO constraint_reader');
    final connectionString = (engine['connectionString'] as String)
        .replaceFirst(RegExp('UID=DBA', caseSensitive: false), 'UID=constraint_reader')
        .replaceFirst(RegExp('PWD=[^;]+', caseSensitive: false), 'PWD=$password');
    final reader = (await service.connect(
      connectionString,
      options: const odbc.ConnectionOptions(maxReconnectAttempts: 0),
    )).getOrThrow();
    final administrator = id;
    id = reader.id;
    try {
      expect(await states('primary', 'constraint_parent'), ['enabled']);
      expect(await states('unique', 'constraint_parent'), ['enabled']);
      expect(await states('foreign', 'constraint_child'), ['enabled']);
      expect(
        (await service.executeQuery(
          'INSERT INTO constraint_parent(id,code) VALUES(99,99)',
          connectionId: id,
        )).isError(),
        isTrue,
      );
      expect(
        (await service.executeQuery("SET TEMPORARY OPTION fire_triggers='Off'", connectionId: id)).isError(),
        isTrue,
      );
    } finally {
      id = administrator;
      await service.disconnect(reader.id);
      await sql('DROP USER constraint_reader');
    }
  });
}
