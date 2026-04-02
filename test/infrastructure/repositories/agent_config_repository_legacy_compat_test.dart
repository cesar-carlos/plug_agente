import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_repository.dart';

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

      final repository = AgentConfigRepository(database);
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
  });
}
