import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

void main() {
  group('AppDatabase (AgentConfigDataSource)', () {
    test('getAllConfigs returns empty list for fresh database', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final rows = await db.getAllConfigs();
      expect(rows, isEmpty);
    });

    test('saveConfig getConfigById getCurrentConfig deleteConfig round-trip', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final older = DateTime.utc(2024);
      final newer = DateTime.utc(2024, 6, 15);

      await db.saveConfig(
        ConfigTableCompanion.insert(
          id: 'cfg-old',
          driverName: 'SQL Server',
          connectionString: 'DSN=Old',
          username: 'sa',
          databaseName: 'db1',
          host: 'localhost',
          port: 1433,
          createdAt: older,
          updatedAt: older,
        ),
      );

      await db.saveConfig(
        ConfigTableCompanion.insert(
          id: 'cfg-new',
          driverName: 'SQL Anywhere',
          connectionString: 'DSN=New',
          username: 'dba',
          databaseName: 'db2',
          host: '127.0.0.1',
          port: 2638,
          createdAt: older,
          updatedAt: newer,
        ),
      );

      final all = await db.getAllConfigs();
      expect(all.length, 2);

      final byId = await db.getConfigById('cfg-new');
      expect(byId, isNotNull);
      expect(byId!.connectionString, 'DSN=New');

      final current = await db.getCurrentConfig();
      expect(current?.id, 'cfg-new');

      await db.deleteConfig('cfg-old');
      expect(await db.getConfigById('cfg-old'), isNull);
      expect((await db.getAllConfigs()).length, 1);
    });

    test('saveConfig updates row on conflict', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final t1 = DateTime.utc(2025);
      await db.saveConfig(
        ConfigTableCompanion.insert(
          id: 'single',
          driverName: 'SQL Server',
          connectionString: 'DSN=Before',
          username: 'u',
          databaseName: 'd',
          host: 'h',
          port: 1,
          createdAt: t1,
          updatedAt: t1,
        ),
      );

      final t2 = DateTime.utc(2025, 2);
      final existing = await db.getConfigById('single');
      expect(existing, isNotNull);
      await db.saveConfig(
        existing!.copyWith(
          connectionString: 'DSN=After',
          updatedAt: t2,
        ),
      );

      final row = await db.getConfigById('single');
      expect(row?.connectionString, 'DSN=After');
      expect(row?.updatedAt.toUtc(), t2);
    });
  });
}
