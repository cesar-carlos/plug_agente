import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('update checkpoint persists WAL writes in a closed snapshot', () async {
    final directory = Directory.systemTemp.createTempSync('plug-update-checkpoint-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final original = File('${directory.path}/original.db');
    final db = AppDatabase(executor: NativeDatabase(original));
    await db.customStatement('CREATE TABLE update_fixture (id INTEGER PRIMARY KEY, value TEXT)');
    await db.customStatement('INSERT INTO update_fixture VALUES (1, ?)', ['snapshot Unicode ação']);
    await db.checkpointAndCloseForUpdate();
    final backup = await original.copy('${directory.path}/snapshot.db');
    final restored = sqlite.sqlite3.open(backup.path);
    try {
      expect(restored.select('SELECT value FROM update_fixture').single['value'], 'snapshot Unicode ação');
      expect(restored.select('PRAGMA user_version').single.values.single, 30);
      expect(restored.select('PRAGMA integrity_check').single.values.single, 'ok');
    } finally {
      restored.close();
    }
  });
}
