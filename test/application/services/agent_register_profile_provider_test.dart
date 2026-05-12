import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/agent_register_profile_provider.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:result_dart/result_dart.dart';

class _MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

void main() {
  group('AgentRegisterProfileProvider', () {
    late _MockAgentConfigRepository repository;
    late AgentRegisterProfileProvider provider;

    setUp(() {
      repository = _MockAgentConfigRepository();
      provider = AgentRegisterProfileProvider(configRepository: repository);
    });

    test('should build register profile snapshot from current config', () async {
      when(() => repository.getCurrentConfig()).thenAnswer(
        (_) async => Success(_validConfig()),
      );

      final snapshot = await provider.loadSnapshot();

      expect(snapshot, isNotNull);
      expect(snapshot?['profile_version'], 7);
      expect(snapshot?['profile_updated_at'], '2026-05-12T10:30:00.000Z');
      expect(
        snapshot?['profile'],
        containsPair('name', 'Empresa Teste Ltda'),
      );
    });

    test('should return null when config cannot be loaded', () async {
      when(() => repository.getCurrentConfig()).thenAnswer(
        (_) async => Failure(domain.NotFoundFailure('No config')),
      );

      final snapshot = await provider.loadSnapshot();

      expect(snapshot, isNull);
    });

    test('should reuse the pending snapshot load for concurrent calls', () async {
      final completer = Completer<Result<Config>>();
      when(() => repository.getCurrentConfig()).thenAnswer((_) => completer.future);

      final first = provider.loadSnapshot();
      final second = provider.loadSnapshot();
      completer.complete(Success(_validConfig()));

      expect(await first, await second);
      verify(() => repository.getCurrentConfig()).called(1);
    });
  });
}

Config _validConfig() {
  return Config(
    id: 'cfg-1',
    driverName: 'SQL Server',
    odbcDriverName: 'ODBC Driver 17 for SQL Server',
    connectionString: '',
    username: 'sa',
    databaseName: 'plug',
    host: 'localhost',
    port: 1433,
    nome: 'Empresa Teste Ltda',
    nomeFantasia: 'Empresa Teste',
    cnaeCnpjCpf: '11222333000181',
    celular: '11999999999',
    email: 'empresa@plug.local',
    endereco: 'Rua Teste',
    numeroEndereco: '10',
    bairro: 'Centro',
    cep: '01001000',
    nomeMunicipio: 'Sao Paulo',
    ufMunicipio: 'SP',
    hubProfileVersion: 7,
    hubProfileUpdatedAt: '2026-05-12T10:30:00.000Z',
    createdAt: DateTime.utc(2026, 5, 12),
    updatedAt: DateTime.utc(2026, 5, 12),
  );
}
