import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_developer_data7_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_connection_catalog.dart';
import 'package:result_dart/result_dart.dart';

String _data7FixturePath(String fileName) {
  return '${Directory.current.path}/test/fixtures/data7/$fileName';
}

void main() {
  group('DeveloperData7ConnectionCatalog', () {
    test('should load single connection from real UTF-8 Data7.Config fixture', () async {
      final catalog = DeveloperData7ConnectionCatalog();
      final fixturePath = _data7FixturePath('data7_config_single_connection.xml');

      final result = await catalog.load(
        actionId: 'action-1',
        configPath: fixturePath,
        phase: 'definition_validation',
      );

      expect(result.isSuccess(), isTrue, reason: result.exceptionOrNull()?.toString());
      final snapshot = result.getOrThrow();
      expect(snapshot.connections, hasLength(1));
      expect(snapshot.connections.single.id, '43134396-D875-4FBB-8EA0-85B2DAFFF69C');
      expect(snapshot.connections.single.label, 'Data7');
      expect(snapshot.connections.single.snapshotHash, startsWith('sha256:'));
    });

    test('should load multiple connections from real UTF-8 Data7.Config fixture', () async {
      final catalog = DeveloperData7ConnectionCatalog();
      final fixturePath = _data7FixturePath('data7_config_multiple_connections.xml');

      final result = await catalog.load(
        actionId: 'action-1',
        configPath: fixturePath,
        phase: 'definition_validation',
      );

      expect(result.isSuccess(), isTrue);
      final snapshot = result.getOrThrow();
      expect(snapshot.connections, hasLength(2));
      expect(snapshot.connections.map((connection) => connection.label), containsAll(['Data7', 'Campo']));
    });

    test('should load a single connection and resolve by id case-insensitively', () async {
      final catalog = DeveloperData7ConnectionCatalog(
        readConfig: (_) async => r'''
<Configuracoes>
  <Item ID="43134396-D875-4FBB-8EA0-85B2DAFFF69C">
    <Descricao>Data7</Descricao>
    <Conexao>
      <Servidor>127.0.0.1\\Data7</Servidor>
      <BaseDados>Estacao</BaseDados>
      <Porta>1433</Porta>
      <RDBMS>MSSQLServer</RDBMS>
    </Conexao>
  </Item>
</Configuracoes>
''',
      );

      final result = await catalog.load(
        actionId: 'action-1',
        configPath: r'C:\Data7\bin\Data7.Config',
        phase: 'definition_validation',
      );

      expect(result.isSuccess(), isTrue);
      final snapshot = result.getOrThrow();
      expect(snapshot.connections, hasLength(1));
      expect(snapshot.connections.single.label, 'Data7');
      expect(
        snapshot.findById('43134396-d875-4fbb-8ea0-85b2dafff69c')?.id,
        '43134396-D875-4FBB-8EA0-85B2DAFFF69C',
      );
      expect(snapshot.connections.single.snapshotHash, startsWith('sha256:'));
    });

    test('should reject duplicated connection ids ignoring case', () async {
      final catalog = DeveloperData7ConnectionCatalog(
        readConfig: (_) async => '''
<Configuracoes>
  <Item ID="43134396-D875-4FBB-8EA0-85B2DAFFF69C">
    <Descricao>Data7</Descricao>
  </Item>
  <Item ID="43134396-d875-4fbb-8ea0-85b2dafff69c">
    <Descricao>Data7 Replica</Descricao>
  </Item>
</Configuracoes>
''',
      );

      final result = await catalog.load(
        actionId: 'action-1',
        configPath: r'C:\Data7\bin\Data7.Config',
        phase: 'definition_validation',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      final actionFailure = failure! as ActionValidationFailure;
      expect(actionFailure.code, 'DEVELOPER_DATA7_CONNECTION_DUPLICATED');
      expect(
        actionFailure.context,
        containsPair('reason', AgentActionDeveloperData7Constants.developerData7ConnectionDuplicatedReason),
      );
    });

    test('should ignore Senha and Usuario when computing snapshot hash', () async {
      const connectionId = '43134396-D875-4FBB-8EA0-85B2DAFFF69C';
      const baseXml =
          '''
<Configuracoes>
  <Item ID="$connectionId">
    <Descricao>Data7</Descricao>
    <Conexao>
      <Servidor>127.0.0.1\\\\Data7</Servidor>
      <BaseDados>Estacao</BaseDados>
      <Porta>1433</Porta>
      <RDBMS>MSSQLServer</RDBMS>
''';

      Future<Result<DeveloperData7ConnectionCatalogSnapshot>> loadWithCredentials({
        required String senha,
        required String usuario,
      }) {
        final catalog = DeveloperData7ConnectionCatalog(
          readConfig: (_) async =>
              '''
$baseXml
      <Senha>$senha</Senha>
      <Usuario>$usuario</Usuario>
    </Conexao>
  </Item>
</Configuracoes>
''',
        );
        return catalog.load(
          actionId: 'action-1',
          configPath: r'C:\Data7\bin\Data7.Config',
          phase: 'definition_validation',
        );
      }

      final withoutSecrets = await loadWithCredentials(senha: '', usuario: '');
      final withSecrets = await loadWithCredentials(senha: 'super-secret', usuario: 'admin');

      expect(withoutSecrets.isSuccess(), isTrue);
      expect(withSecrets.isSuccess(), isTrue);
      expect(
        withoutSecrets.getOrThrow().connections.single.snapshotHash,
        withSecrets.getOrThrow().connections.single.snapshotHash,
      );
    });

    test('should not leak Senha from config in validation failures', () async {
      final catalog = DeveloperData7ConnectionCatalog(
        readConfig: (_) async => '''
<Configuracoes>
  <Item ID="43134396-D875-4FBB-8EA0-85B2DAFFF69C">
    <Conexao>
      <Senha>super-secret-password</Senha>
    </Conexao>
  </Item>
''',
      );

      final result = await catalog.load(
        actionId: 'action-1',
        configPath: r'C:\Data7\bin\Data7.Config',
        phase: 'definition_validation',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      final serialized = '${failure.message} ${failure.context.values.join(' ')}';
      expect(serialized, isNot(contains('super-secret-password')));
    });

    test('should load connections from UTF-8 Data7.Config with accented element names', () async {
      final catalog = DeveloperData7ConnectionCatalog(
        readConfig: (_) async => '''
<Configurações>
  <ArquivosVersao></ArquivosVersao>
  <Item ID="1C19CB87-D23E-45E0-88BA-1DE41370DECD">
    <Descrição>Estacao</Descrição>
    <Conexão>
      <Servidor>localhost</Servidor>
      <BaseDados>Estacao</BaseDados>
      <Porta>1433</Porta>
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
''',
      );

      final result = await catalog.load(
        actionId: 'action-1',
        configPath: r'C:\Data7\bin\Data7.Config',
        phase: 'definition_validation',
      );

      expect(result.isSuccess(), isTrue);
      final snapshot = result.getOrThrow();
      expect(snapshot.connections, hasLength(2));
      expect(snapshot.connections.map((connection) => connection.label), containsAll(['Estacao', 'Campo']));
    });

    test('should decode UTF-8 BOM files from disk', () async {
      final tempDir = await Directory.systemTemp.createTemp('data7_bom_test_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final configFile = File('${tempDir.path}${Platform.pathSeparator}Data7.Config');
      final fixtureBytes = await File(_data7FixturePath('data7_config_single_connection.xml')).readAsBytes();
      await configFile.writeAsBytes(<int>[0xEF, 0xBB, 0xBF, ...fixtureBytes]);

      final catalog = DeveloperData7ConnectionCatalog();
      final result = await catalog.load(
        actionId: 'action-1',
        configPath: configFile.path,
        phase: 'definition_validation',
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().connections.single.label, 'Data7');
    });

    test('should reject malformed xml', () async {
      final catalog = DeveloperData7ConnectionCatalog(
        readConfig: (_) async => '<Configuracoes><Item>',
      );

      final result = await catalog.load(
        actionId: 'action-1',
        configPath: r'C:\Data7\bin\Data7.Config',
        phase: 'definition_validation',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect((failure! as ActionValidationFailure).code, 'DEVELOPER_DATA7_CONFIG_INVALID');
    });
  });
}
