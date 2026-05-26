import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_developer_data7_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_connection_catalog.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  group('DeveloperData7ConnectionCatalog', () {
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
