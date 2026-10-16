import 'dart:io';
import 'package:odbc_fast/odbc_fast.dart' as odbc;

/// Fixed operator-only setup; called after the companion verifies its private database.
Future<void> provisionWideStructureFixture(odbc.OdbcService service, String connectionId) async {
  for (var index = 0; index < 15; index++) {
    final name = 'wide_${index.toString().padLeft(2, '0')}';
    for (final sql in [
      'CREATE TABLE $name (tenant_id INTEGER NOT NULL, item_id INTEGER NOT NULL, marker INTEGER NOT NULL, PRIMARY KEY(tenant_id,item_id))',
      'INSERT INTO $name (tenant_id,item_id,marker) VALUES(1,10,100)',
      'INSERT INTO $name (tenant_id,item_id,marker) VALUES(2,20,200)',
    ]) {
      (await service.executeQuery(sql, connectionId: connectionId)).getOrThrow();
    }
  }
  for (final sql in [
    'CREATE TABLE rel_left (tenant_id INTEGER NOT NULL, left_id INTEGER NOT NULL, PRIMARY KEY(tenant_id,left_id))',
    'CREATE TABLE rel_right (tenant_id INTEGER NOT NULL, right_id INTEGER NOT NULL, PRIMARY KEY(tenant_id,right_id))',
    'CREATE TABLE rel_link (tenant_id INTEGER NOT NULL, left_id INTEGER NOT NULL, right_id INTEGER NOT NULL, PRIMARY KEY(tenant_id,left_id,right_id), CONSTRAINT fk_rel_left FOREIGN KEY(tenant_id,left_id) REFERENCES rel_left(tenant_id,left_id), CONSTRAINT fk_rel_right FOREIGN KEY(tenant_id,right_id) REFERENCES rel_right(tenant_id,right_id))',
    'INSERT INTO rel_left VALUES(1,10)',
    'INSERT INTO rel_left VALUES(1,20)',
    'INSERT INTO rel_right VALUES(1,100)',
    'INSERT INTO rel_right VALUES(1,200)',
    'INSERT INTO rel_link VALUES(1,10,100)',
    'INSERT INTO rel_link VALUES(1,10,200)',
    'INSERT INTO rel_link VALUES(1,20,100)',
  ]) {
    (await service.executeQuery(sql, connectionId: connectionId)).getOrThrow();
  }
  for (final name in ['wide_15', 'wide_hidden']) {
    (await service.executeQuery(
      'CREATE VIEW $name AS SELECT tenant_id,item_id,marker FROM wide_14',
      connectionId: connectionId,
    )).getOrThrow();
  }
}

/// No caller SQL, identifiers or values. Wide changes target only wide_07; FK removal targets only rel_link.
Future<bool> changeWideStructureFixture(
  odbc.OdbcService service, {
  required String connectionString,
  required String database,
  required String engine,
  required String kind,
}) async {
  final identitySql = switch (engine) {
    'postgres' => 'SELECT CURRENT_DATABASE()',
    'mssql' || 'sybase' => 'SELECT DB_NAME()',
    'firebird' => r'SELECT MON$DATABASE_NAME FROM MON$DATABASE',
    _ => throw StateError('Unsupported fixture engine.'),
  };
  final sql = switch (kind) {
    'relationship-drop-right-fk' => 'ALTER TABLE rel_link DROP CONSTRAINT fk_rel_right',
    'wide-add-unrelated-column' => 'ALTER TABLE wide_07 ADD extra_note INTEGER',
    'wide-change-trained-column' => switch (engine) {
      'postgres' => 'ALTER TABLE wide_07 ALTER COLUMN marker TYPE BIGINT',
      'mssql' => 'ALTER TABLE wide_07 ALTER COLUMN marker BIGINT NOT NULL',
      'sybase' => 'ALTER TABLE wide_07 ALTER marker BIGINT NOT NULL',
      'firebird' => 'ALTER TABLE wide_07 ALTER marker TYPE BIGINT',
      _ => throw StateError('Unsupported fixture engine.'),
    },
    _ => throw StateError('Unknown structural fixture action.'),
  };
  final connectionId = (await service.connect(
    connectionString,
    options: const odbc.ConnectionOptions(maxReconnectAttempts: 0),
  )).getOrThrow().id;
  try {
    final actual = (await service.executeQuery(
      identitySql,
      connectionId: connectionId,
    )).getOrThrow().rows.single.single.toString();
    if (engine == 'firebird'
        ? File(actual).absolute.path.toLowerCase() != File(database).absolute.path.toLowerCase()
        : actual != database) {
      throw StateError('Actual private fixture database mismatch.');
    }
    (await service.executeQuery(sql, connectionId: connectionId)).getOrThrow();
    return true;
  } finally {
    (await service.disconnect(connectionId)).getOrThrow();
  }
}
