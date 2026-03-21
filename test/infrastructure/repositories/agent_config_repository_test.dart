import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_repository.dart';

void main() {
  late AppDatabase database;
  late AgentConfigRepository repository;

  Config buildConfig({required String id}) {
    final now = DateTime.utc(2026, 3);
    return Config(
      id: id,
      driverName: 'SQL Server',
      odbcDriverName: 'ODBC Driver 17 for SQL Server',
      connectionString: 'DSN=Test',
      username: 'u',
      databaseName: 'db',
      host: 'localhost',
      port: 1433,
      createdAt: now,
      updatedAt: now,
      agentId: 'agent-1',
    );
  }

  setUp(() {
    database = AppDatabase(executor: NativeDatabase.memory());
    repository = AgentConfigRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('AgentConfigRepository', () {
    test('should return NotFoundFailure when getById misses', () async {
      final result = await repository.getById('missing');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<domain.NotFoundFailure>());
    });

    test(
      'should return NotFoundFailure when getCurrentConfig and table empty',
      () async {
        final result = await repository.getCurrentConfig();

        expect(result.isError(), isTrue);
        expect(result.exceptionOrNull(), isA<domain.NotFoundFailure>());
      },
    );

    test('should save and load config by id', () async {
      final config = buildConfig(id: 'cfg-1');
      final saveResult = await repository.save(config);

      expect(saveResult.isSuccess(), isTrue);

      final byId = await repository.getById('cfg-1');
      expect(byId.isSuccess(), isTrue);
      expect(byId.getOrNull()!.host, 'localhost');
      expect(byId.getOrNull()!.driverName, 'SQL Server');
    });

    test('should list all saved configs', () async {
      await repository.save(buildConfig(id: 'a'));
      await repository.save(buildConfig(id: 'b'));

      final all = await repository.getAll();

      expect(all.isSuccess(), isTrue);
      expect(all.getOrNull(), hasLength(2));
      final ids = all.getOrNull()!.map((Config c) => c.id).toSet();
      expect(ids, containsAll(<String>['a', 'b']));
    });

    test('should return latest updated config from getCurrentConfig', () async {
      final older = buildConfig(id: 'old');
      await repository.save(older);
      final newer = older.copyWith(
        id: 'new',
        updatedAt: older.updatedAt.add(const Duration(days: 1)),
      );
      await repository.save(newer);

      final current = await repository.getCurrentConfig();

      expect(current.isSuccess(), isTrue);
      expect(current.getOrNull()!.id, 'new');
    });

    test('should delete configuration', () async {
      await repository.save(buildConfig(id: 'del-me'));
      final deleted = await repository.delete('del-me');

      expect(deleted.isSuccess(), isTrue);

      final again = await repository.getById('del-me');
      expect(again.isError(), isTrue);
    });
  });
}
