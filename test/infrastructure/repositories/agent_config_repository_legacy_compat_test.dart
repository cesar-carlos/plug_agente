import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/value_objects/hub_auth_secrets.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_repository.dart';

class _FakeHubAuthSecretStore implements IHubAuthSecretStore {
  final Map<String, HubAuthSecrets> _storage = <String, HubAuthSecrets>{};

  @override
  bool get isAvailable => true;

  @override
  Future<void> deleteSecrets(String configId) async {
    _storage.remove(configId);
  }

  @override
  Future<HubAuthSecrets> readSecrets(String configId) async {
    return _storage[configId] ?? const HubAuthSecrets();
  }

  @override
  Future<void> saveSecrets(String configId, HubAuthSecrets secrets) async {
    _storage[configId] = secrets;
  }
}

void main() {
  group('AgentConfigRepository legacy compatibility', () {
    test('should load legacy-like row with profile defaults', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);

      final nowEpochMs = DateTime.utc(2025).millisecondsSinceEpoch;
      await database.customStatement(
        '''
        INSERT INTO config_table (
          id,
          server_url,
          agent_id,
          driver_name,
          odbc_driver_name,
          connection_string,
          username,
          password,
          database_name,
          host,
          port,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        <Object?>[
          'legacy-config',
          'https://legacy.example.com',
          'legacy-agent',
          'SQL Server',
          'ODBC Driver 17 for SQL Server',
          '',
          'sa',
          'secret',
          'legacy_db',
          'localhost',
          1433,
          nowEpochMs,
          nowEpochMs,
        ],
      );

      final repository = AgentConfigRepository(
        database,
        authSecretStore: _FakeHubAuthSecretStore(),
      );
      final result = await repository.getCurrentConfig();

      expect(result.isSuccess(), isTrue);
      final config = result.getOrThrow();
      expect(config.id, equals('legacy-config'));
      expect(config.nome, isEmpty);
      expect(config.nomeFantasia, isEmpty);
      expect(config.cnaeCnpjCpf, isEmpty);
      expect(config.telefone, isEmpty);
      expect(config.email, isEmpty);
      expect(config.endereco, isEmpty);
      expect(config.cep, isEmpty);
      expect(config.observacao, isEmpty);
    });

    test('should migrate legacy auth secrets into secure storage on load', () async {
      final database = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(database.close);
      final secretStore = _FakeHubAuthSecretStore();

      final nowEpochMs = DateTime.utc(2025).millisecondsSinceEpoch;
      await database.customStatement(
        '''
        INSERT INTO config_table (
          id,
          server_url,
          agent_id,
          auth_token,
          refresh_token,
          auth_username,
          auth_password,
          driver_name,
          odbc_driver_name,
          connection_string,
          username,
          password,
          database_name,
          host,
          port,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        <Object?>[
          'legacy-secrets',
          'https://legacy.example.com',
          'legacy-agent',
          'access-token',
          'refresh-token',
          'agent_user',
          'agent_pass',
          'SQL Server',
          'ODBC Driver 17 for SQL Server',
          '',
          'sa',
          'secret',
          'legacy_db',
          'localhost',
          1433,
          nowEpochMs,
          nowEpochMs,
        ],
      );

      final repository = AgentConfigRepository(
        database,
        authSecretStore: secretStore,
      );

      final result = await repository.getCurrentConfig();

      expect(result.isSuccess(), isTrue);
      final config = result.getOrThrow();
      expect(config.authToken, 'access-token');
      expect(config.refreshToken, 'refresh-token');
      expect(config.authPassword, 'agent_pass');

      final storedSecrets = await secretStore.readSecrets('legacy-secrets');
      expect(storedSecrets.authToken, 'access-token');
      expect(storedSecrets.refreshToken, 'refresh-token');
      expect(storedSecrets.authPassword, 'agent_pass');
    });
  });
}
