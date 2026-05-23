import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_config_locator.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_connection_catalog.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_definition_resolver.dart';

void main() {
  group('DeveloperData7ActionAdapter', () {
    test('should validate active definition and expose safe diagnostics', () async {
      final adapter = DeveloperData7ActionAdapter(
        definitionResolver: _resolverForCatalog('''
<Configuracoes>
  <Item ID="34512A51-672C-4ECE-9991-F43E175E7A8B">
    <Descricao>Estacao</Descricao>
    <Conexao>
      <Servidor>localhost</Servidor>
      <BaseDados>Estacao</BaseDados>
      <Porta>1433</Porta>
      <RDBMS>MSSQLServer</RDBMS>
    </Conexao>
  </Item>
</Configuracoes>
'''),
      );

      final result = await adapter.validateDefinition(_definition());

      expect(result.isSuccess(), isTrue);
      final preflight = result.getOrThrow();
      expect(preflight.canRun, isTrue);
      expect(preflight.redactedDiagnostics, containsPair('engine', 'data7Executor'));
      expect(preflight.redactedDiagnostics, containsPair('connection_label', 'Estacao'));
    });

    test('should normalize canonical paths and connection metadata before save', () async {
      final validatedAt = DateTime.utc(2026, 5, 15, 12, 30);
      final adapter = DeveloperData7ActionAdapter(
        definitionResolver: _resolverForCatalog(
          '''
<Configuracoes>
  <Item ID="34512A51-672C-4ECE-9991-F43E175E7A8B">
    <Descricao>Campo</Descricao>
    <Conexao>
      <Servidor>localhost</Servidor>
      <BaseDados>Campo</BaseDados>
      <Porta>1433</Porta>
      <RDBMS>MSSQLServer</RDBMS>
    </Conexao>
  </Item>
</Configuracoes>
''',
          now: () => validatedAt,
        ),
      );

      final result = await adapter.normalizeDefinition(_definition(connectionLabel: 'stale'));

      expect(result.isSuccess(), isTrue);
      final config = result.getOrThrow().config as DeveloperActionConfig;
      expect(config.connectionLabel, 'Campo');
      expect(config.connectionSnapshotHash, startsWith('sha256:'));
      expect(config.executorPath.canonicalPath, r'C:\Data7\bin\Executor.exe');
      expect(config.projectPath.canonicalPath, r'C:\Data7\Transmissao\Transmissor.7Proj');
      expect(config.data7ConfigPath.canonicalPath, r'C:\Data7\bin\Data7.Config');
      expect(config.executorPath.validatedAt, validatedAt);
    });

    test('should reject runtime overrides during execution preflight', () async {
      final adapter = DeveloperData7ActionAdapter(
        definitionResolver: _resolverForCatalog('''
<Configuracoes>
  <Item ID="34512A51-672C-4ECE-9991-F43E175E7A8B">
    <Descricao>Estacao</Descricao>
  </Item>
</Configuracoes>
'''),
      );

      final result = await adapter.prepareExecution(
        definition: _definition(),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          contextPath: r'C:\Temp\context.json',
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect(
        (failure! as ActionValidationFailure).code,
        'DEVELOPER_DATA7_CONTEXT_NOT_SUPPORTED',
      );
    });

    test('should reject execution when connection snapshot changed after save', () async {
      final adapter = DeveloperData7ActionAdapter(
        definitionResolver: _resolverForCatalog('''
<Configuracoes>
  <Item ID="34512A51-672C-4ECE-9991-F43E175E7A8B">
    <Descricao>Producao</Descricao>
    <Conexao>
      <Servidor>10.0.0.1</Servidor>
      <BaseDados>Prod</BaseDados>
      <Porta>1433</Porta>
      <RDBMS>MSSQLServer</RDBMS>
    </Conexao>
  </Item>
</Configuracoes>
'''),
      );

      final result = await adapter.prepareExecution(
        definition: _definition(connectionSnapshotHash: 'sha256:old'),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect(
        (failure! as ActionValidationFailure).code,
        'DEVELOPER_DATA7_CONNECTION_SNAPSHOT_MISMATCH',
      );
    });
  });
}

DeveloperData7DefinitionResolver _resolverForCatalog(
  String catalogXml, {
  DateTime Function()? now,
}) {
  final pathValidator = ActionPathValidator(
    fileExists: (_) async => true,
    directoryExists: (_) async => true,
    canonicalizeFile: (path) async => path,
    canonicalizeDirectory: (path) async => path,
    fileLength: (_) async => 32,
    readText: (_) async => '{}',
    launchAccessValidator: ({required actionId, required field, required path, required phase}) => null,
  );
  return DeveloperData7DefinitionResolver(
    pathValidator: pathValidator,
    configLocator: DeveloperData7ConfigLocator(pathValidator: pathValidator),
    connectionCatalog: DeveloperData7ConnectionCatalog(
      readConfig: (_) async => catalogXml,
    ),
    now: now,
  );
}

AgentActionDefinition _definition({
  String connectionLabel = 'Data7',
  String? connectionSnapshotHash,
}) {
  return AgentActionDefinition(
    id: 'action-1',
    name: 'Transmitir projeto',
    state: AgentActionState.active,
    config: DeveloperActionConfig.data7Executor(
      executorPath: const AgentActionPathReference(
        originalPath: r'C:\Data7\bin\Executor.exe',
      ),
      projectPath: const AgentActionPathReference(
        originalPath: r'C:\Data7\Transmissao\Transmissor.7Proj',
      ),
      data7ConfigPath: const AgentActionPathReference(
        originalPath: r'C:\Data7\bin\Data7.Config',
      ),
      connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
      connectionLabel: connectionLabel,
      connectionSnapshotHash: connectionSnapshotHash,
    ),
  );
}
