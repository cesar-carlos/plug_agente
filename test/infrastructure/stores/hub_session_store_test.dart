import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/stores/hub_session_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_hub_auth_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/secure_storage_guard.dart';

Future<void> _insertConfig(AppDatabase database, String id) async {
  final now = DateTime.utc(2025);
  await database.into(database.configTable).insert(
    ConfigTableCompanion.insert(
      id: id,
      serverUrl: const Value('https://hub.example.com'),
      agentId: const Value('agent-1'),
      driverName: 'SQL Server',
      odbcDriverName: const Value('ODBC Driver 17 for SQL Server'),
      connectionString: '',
      username: 'sa',
      databaseName: 'legacy_db',
      host: 'localhost',
      port: 1433,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

void main() {
  group('HubSessionStore', () {
    late AppDatabase database;

    setUp(() async {
      database = AppDatabase(executor: NativeDatabase.memory());
      await _insertConfig(database, 'cfg-1');
    });

    tearDown(() async {
      await database.close();
    });

    test('should fail closed when writing session tokens with noop secret store', () async {
      final store = HubSessionStore(
        database,
        authSecretStore: NoopHubAuthSecretStore(),
      );

      final result = await store.writeSessionTokens(
        'cfg-1',
        const AuthToken(token: 'access', refreshToken: 'refresh'),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.ConfigurationFailure;
      expect(failure.context['reason'], SecureStorageGuard.unavailableReason);

      final row = await (database.select(database.configTable)
            ..where((tbl) => tbl.id.equals('cfg-1')))
          .getSingle();
      expect(row.authToken, isNull);
      expect(row.refreshToken, isNull);
    });
  });
}
