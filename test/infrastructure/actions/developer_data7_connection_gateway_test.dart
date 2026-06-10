import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_config_locator.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_connection_catalog.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_connection_gateway.dart';

void main() {
  group('DeveloperData7ConnectionGateway', () {
    late Directory tempDir;
    late File configFile;
    late DeveloperData7ConnectionGateway gateway;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('data7_config_test_');
      configFile = File('${tempDir.path}${Platform.pathSeparator}Data7.Config');
      await configFile.writeAsString('''
<Configurações>
  <ArquivosVersao></ArquivosVersao>
  <Item ID="1C19CB87-D23E-45E0-88BA-1DE41370DECD">
    <Descrição>Estacao</Descrição>
    <Conexão>
      <Servidor>localhost</Servidor>
      <BaseDados>Estacao</BaseDados>
      <Porta>1433</Porta>
      <Usuario>sa</Usuario>
      <Senha>secret</Senha>
      <RDBMS>MSSQLServer</RDBMS>
    </Conexão>
  </Item>
  <Item ID="1DA725C7-129C-4D53-84A1-CA55B80057E6">
    <Descrição>Campo</Descrição>
    <Conexão>
      <Servidor>localhost</Servidor>
      <BaseDados>Campo</BaseDados>
      <Porta>1433</Porta>
      <RDBMS>MSSQLServer</RDBMS>
    </Conexão>
  </Item>
</Configurações>
''');

      gateway = DeveloperData7ConnectionGateway(
        configLocator: DeveloperData7ConfigLocator(pathValidator: ActionPathValidator()),
        connectionCatalog: DeveloperData7ConnectionCatalog(),
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('lists single connection from real Data7.Config fixture for dropdown', () async {
      final fixturePath =
          '${Directory.current.path}${Platform.pathSeparator}test${Platform.pathSeparator}fixtures${Platform.pathSeparator}data7${Platform.pathSeparator}data7_config_single_connection.xml';
      final fixtureFile = File(fixturePath);
      expect(fixtureFile.existsSync(), isTrue, reason: 'Fixture not found: $fixturePath');

      final fixtureConfigFile = File('${tempDir.path}${Platform.pathSeparator}Data7.Config');
      await fixtureConfigFile.writeAsBytes(await fixtureFile.readAsBytes());

      final result = await gateway.listConnections(
        DeveloperData7ConnectionLookupRequest(
          actionId: 'action-1',
          data7ConfigPath: AgentActionPathReference(originalPath: fixtureConfigFile.path),
        ),
      );

      expect(result.isSuccess(), isTrue, reason: result.exceptionOrNull()?.toString());
      final lookup = result.getOrThrow();
      expect(lookup.connections, hasLength(1));
      expect(lookup.connections.single.id, '43134396-D875-4FBB-8EA0-85B2DAFFF69C');
      expect(lookup.connections.single.label, 'Data7');
    });

    test('lists connections from a real UTF-8 Data7.Config file on disk', () async {
      final result = await gateway.listConnections(
        DeveloperData7ConnectionLookupRequest(
          actionId: 'action-1',
          data7ConfigPath: AgentActionPathReference(originalPath: configFile.path),
        ),
      );

      expect(result.isSuccess(), isTrue);
      final lookup = result.getOrThrow();
      expect(lookup.connections, hasLength(2));
      expect(lookup.connections.map((c) => c.label), containsAll(['Estacao', 'Campo']));
      expect(lookup.resolvedConfigPath.displayPath, configFile.path);
      expect(lookup.usedDefaultLocation, isFalse);
    });

    test('ignores working directory allowlist when listing editor connections', () async {
      final result = await gateway.listConnections(
        DeveloperData7ConnectionLookupRequest(
          actionId: 'action-1',
          data7ConfigPath: AgentActionPathReference(originalPath: configFile.path),
          pathPolicy: const AgentActionPathPolicy(allowedWorkingDirectories: {r'C:\Other'}),
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().connections, hasLength(2));
    });

    test('lists connections in production profile without working directory allowlist', () async {
      dotenv.loadFromString(envString: 'AGENT_OPERATIONAL_PROFILE=prod');

      final result = await gateway.listConnections(
        DeveloperData7ConnectionLookupRequest(
          actionId: 'action-1',
          data7ConfigPath: AgentActionPathReference(originalPath: configFile.path),
        ),
      );

      expect(result.isSuccess(), isTrue, reason: result.exceptionOrNull()?.toString());
      expect(result.getOrThrow().connections, isNotEmpty);
    });

    test('surfaces parse failure when config has no connection items', () async {
      await configFile.writeAsString('<Configurações><ArquivosVersao></ArquivosVersao></Configurações>');

      final result = await gateway.listConnections(
        DeveloperData7ConnectionLookupRequest(
          actionId: 'action-1',
          data7ConfigPath: AgentActionPathReference(originalPath: configFile.path),
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.code, 'DEVELOPER_DATA7_CONNECTION_MISSING');
    });
  });

  group('DeveloperData7ConnectionGateway live file', () {
    const livePath = r'C:\Data7\bin\Data7.Config';

    test(
      'loads connections from installed Data7.Config when present',
      () async {
        if (!File(livePath).existsSync()) {
          return;
        }

        final gateway = DeveloperData7ConnectionGateway(
          configLocator: DeveloperData7ConfigLocator(pathValidator: ActionPathValidator()),
          connectionCatalog: DeveloperData7ConnectionCatalog(),
        );

        final result = await gateway.listConnections(
          const DeveloperData7ConnectionLookupRequest(
            actionId: 'action-live',
            data7ConfigPath: AgentActionPathReference(originalPath: livePath),
          ),
        );

        expect(result.isSuccess(), isTrue, reason: result.exceptionOrNull()?.toString());
        expect(result.getOrThrow().connections, isNotEmpty);
      },
      skip: !File(livePath).existsSync() ? r'C:\Data7\bin\Data7.Config not installed' : false,
    );
  });
}
