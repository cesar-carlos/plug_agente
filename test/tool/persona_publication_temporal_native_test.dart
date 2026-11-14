import 'dart:io';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:test/test.dart';
import '../../tool/homologation/persona_publication_fixture.dart';

void main() {
  final connection = Platform.environment['PUBLICATION_TEMPORAL_MSSQL'];
  final database = Platform.environment['PUBLICATION_TEMPORAL_DATABASE'];
  test('native fixture preserves final millisecond, excludes next day and retains null', () async {
    if (database == null ||
        !RegExp(r'^se7e_persona_[a-f0-9]{12}_test$').hasMatch(database) ||
        connection == null ||
        !connection.contains('SERVER=127.0.0.1,') ||
        !connection.contains('DATABASE=$database;')) {
      throw StateError('Explicit disposable local fixture required.');
    }
    final locator = odbc.ServiceLocator()..initialize();
    final service = locator.syncService;
    (await service.initialize()).getOrThrow();
    final fixture = PublicationFixture(service, connection, database, 'mssql', [
      {
        'table': 'publication_temporal',
        'columns': [
          {'name': 'id', 'type': 'integer', 'nullable': false, 'generated': false},
          {'name': 'at', 'type': 'date', 'temporalStorage': 'datetime2_3', 'nullable': true, 'generated': false},
        ],
        'primaryKey': ['id'],
        'uniqueKeys': <List<String>>[],
      },
    ]);
    await fixture.initialize();
    final values = ['2026-11-10T23:59:59.997Z', '2026-11-11T00:00:00.000Z', '2026-11-10', null];
    await fixture.prepare([
      {
        'table': 'publication_temporal',
        'rows': [
          for (var i = 0; i < values.length; i++)
            {
              'id': {'type': 'integer', 'value': '${i + 1}'},
              'at': {'type': values[i] == null ? 'null' : 'date', 'value': values[i]},
            },
        ],
      },
    ]);
    final id = (await service.connect(
      connection,
      options: const odbc.ConnectionOptions(maxReconnectAttempts: 0),
    )).getOrThrow().id;
    try {
      final rows = (await service.executeQuery(
        'SELECT id, CONVERT(varchar(23), [at], 126), DATEPART(millisecond, [at]) FROM publication_temporal ORDER BY id',
        connectionId: id,
      )).getOrThrow().rows;
      expect(rows.map((r) => r[1]).toList(), [
        '2026-11-10T23:59:59.997',
        '2026-11-11T00:00:00',
        '2026-11-10T00:00:00',
        null,
      ]);
      expect(rows.map((r) => r[2]?.toString()).toList(), ['997', '0', '0', null]);
      final selected = (await service.executeQuery(
        "SELECT id FROM publication_temporal WHERE [at] >= '2026-11-10' AND [at] < DATEADD(day,1,CAST('2026-11-10' AS date)) ORDER BY id",
        connectionId: id,
      )).getOrThrow().rows;
      expect(selected.map((r) => r[0].toString()).toList(), ['1', '3']);
    } finally {
      (await service.disconnect(id)).getOrThrow();
      locator.shutdown();
    }
  }, skip: connection == null ? 'Explicit private MSSQL fixture required; never uses operational DSNs.' : false);
}
