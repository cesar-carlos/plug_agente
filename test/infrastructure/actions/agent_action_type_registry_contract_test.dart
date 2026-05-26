import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/com_object_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/com_object_action_runner.dart';
import 'package:plug_agente/infrastructure/actions/com_object_invocation_registry.dart';
import 'package:plug_agente/infrastructure/actions/command_line_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/command_line_action_process_runner.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_config_locator.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_connection_catalog.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_definition_resolver.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_process_runner.dart';
import 'package:plug_agente/infrastructure/actions/email_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/email_action_mailer_runner.dart';
import 'package:plug_agente/infrastructure/actions/executable_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/executable_action_process_runner.dart';
import 'package:plug_agente/infrastructure/actions/jar_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/jar_action_process_runner.dart';
import 'package:plug_agente/infrastructure/actions/script_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/script_action_process_runner.dart';
import 'package:plug_agente/infrastructure/stores/noop_agent_action_secret_store.dart';

import '../../../tool/agent_action_security_gate_checklist.dart';

/// Mirrors production registration in `plug_dependency_registrar` for MVP 5 types.
({
  AgentActionAdapterRegistry adapters,
  AgentActionLocalRunnerRegistry runners,
})
buildMvp5AgentActionRegistries() {
  final pathValidator = ActionPathValidator(
    fileExists: (_) async => true,
    directoryExists: (_) async => true,
    canonicalizeFile: (path) async => path,
    canonicalizeDirectory: (path) async => path,
    fileLength: (_) async => 32,
    readText: (_) async => '{}',
  );
  const secretStore = NoopAgentActionSecretStore();
  final configLocator = DeveloperData7ConfigLocator(pathValidator: pathValidator);
  const catalogXml = '''
<Configuracoes>
  <Item ID="34512A51-672C-4ECE-9991-F43E175E7A8B">
    <Descricao>Contract</Descricao>
    <Conexao>
      <Servidor>localhost</Servidor>
      <BaseDados>Contract</BaseDados>
      <Porta>1433</Porta>
      <RDBMS>MSSQLServer</RDBMS>
    </Conexao>
  </Item>
</Configuracoes>
''';
  final definitionResolver = DeveloperData7DefinitionResolver(
    pathValidator: pathValidator,
    configLocator: configLocator,
    connectionCatalog: DeveloperData7ConnectionCatalog(
      readConfig: (_) async => catalogXml,
    ),
  );
  final comObjectRegistry = ComObjectInvocationRegistry(const <RegisteredComObjectInvocation>[]);

  final adapters = AgentActionAdapterRegistry([
    CommandLineActionAdapter(pathValidator: pathValidator),
    ExecutableActionAdapter(pathValidator: pathValidator),
    ScriptActionAdapter(pathValidator: pathValidator),
    JarActionAdapter(pathValidator: pathValidator),
    EmailActionAdapter(
      pathValidator: pathValidator,
      secretStore: secretStore,
    ),
    ComObjectActionAdapter(
      invocationRegistry: comObjectRegistry,
      pathValidator: pathValidator,
    ),
    DeveloperData7ActionAdapter(definitionResolver: definitionResolver),
  ]);

  final runners = AgentActionLocalRunnerRegistry([
    CommandLineActionProcessRunner(pathValidator: pathValidator),
    ExecutableActionProcessRunner(pathValidator: pathValidator),
    ScriptActionProcessRunner(pathValidator: pathValidator),
    JarActionProcessRunner(pathValidator: pathValidator),
    EmailActionMailerRunner(
      pathValidator: pathValidator,
      secretStore: secretStore,
    ),
    ComObjectActionRunner(
      invocationRegistry: comObjectRegistry,
      pathValidator: pathValidator,
    ),
    DeveloperData7ProcessRunner(definitionResolver: definitionResolver),
  ]);

  return (adapters: adapters, runners: runners);
}

void main() {
  group('AgentAction MVP5 registry contract', () {
    test('should register adapter and local runner for every executable action type', () {
      final registries = buildMvp5AgentActionRegistries();
      const executableTypes = <AgentActionType>[
        AgentActionType.commandLine,
        AgentActionType.executable,
        AgentActionType.script,
        AgentActionType.jar,
        AgentActionType.email,
        AgentActionType.comObject,
        AgentActionType.developer,
      ];

      for (final type in executableTypes) {
        expect(
          registries.adapters.resolve(type).isSuccess(),
          isTrue,
          reason: 'missing adapter for ${type.name}',
        );
        expect(
          registries.runners.resolve(type).isSuccess(),
          isTrue,
          reason: 'missing local runner for ${type.name}',
        );
      }

      expect(registries.adapters.supportedTypes, containsAll(executableTypes));
      expect(registries.runners.supportedTypes, containsAll(executableTypes));
    });

    test('should keep adapter and runner supported type sets aligned', () {
      final registries = buildMvp5AgentActionRegistries();

      expect(
        registries.adapters.supportedTypes.toSet(),
        registries.runners.supportedTypes.toSet(),
      );
    });

    test('security gate checklist should cover every MVP registry type', () {
      final registries = buildMvp5AgentActionRegistries();
      final registryTypeNames = registries.adapters.supportedTypes.map((AgentActionType type) => type.name).toList()
        ..sort();
      final gateTypes = List<String>.from(agentActionSecurityGateMvpTypes)..sort();

      expect(gateTypes, registryTypeNames);
    });

    test('should resolve every MVP adapter type for validateDefinition entry point', () async {
      final registries = buildMvp5AgentActionRegistries();
      const definition = AgentActionDefinition(
        id: 'contract-draft',
        name: 'Contract',
        config: CommandLineActionConfig(command: 'echo contract'),
      );

      for (final type in registries.adapters.supportedTypes) {
        final adapterResult = registries.adapters.resolve(type);
        expect(adapterResult.isSuccess(), isTrue, reason: 'resolve failed for ${type.name}');

        final typedDefinition = AgentActionDefinition(
          id: definition.id,
          name: definition.name,
          state: definition.state,
          config: switch (type) {
            AgentActionType.commandLine => definition.config,
            AgentActionType.executable => const ExecutableActionConfig(
              executablePath: AgentActionPathReference(originalPath: r'C:\Windows\System32\cmd.exe'),
            ),
            AgentActionType.script => const ScriptActionConfig(
              scriptPath: AgentActionPathReference(originalPath: r'C:\Temp\script.ps1'),
            ),
            AgentActionType.jar => const JarActionConfig(
              jarPath: AgentActionPathReference(originalPath: r'C:\Temp\app.jar'),
            ),
            AgentActionType.email => const EmailActionConfig(
              smtpProfileId: 'default',
              from: 'agent@local',
              to: <String>['ops@local'],
              subjectTemplate: 'subject',
              bodyTemplate: 'body',
            ),
            AgentActionType.comObject => const ComObjectActionConfig(
              progId: 'AgentAction.Test',
              memberName: 'Ping',
            ),
            AgentActionType.developer => DeveloperActionConfig.data7Executor(
              executorPath: const AgentActionPathReference(originalPath: r'C:\Data7\bin\Executor.exe'),
              projectPath: const AgentActionPathReference(originalPath: r'C:\Data7\proj.7Proj'),
              data7ConfigPath: const AgentActionPathReference(originalPath: r'C:\Data7\bin\Data7.Config'),
              connectionId: '34512A51-672C-4ECE-9991-F43E175E7A8B',
              connectionLabel: 'Contract',
            ),
          },
        );

        final validation = await adapterResult.getOrThrow().validateDefinition(typedDefinition);
        expect(
          validation.isSuccess(),
          isTrue,
          reason: 'validateDefinition should succeed for minimal ${type.name} draft',
        );
      }
    });
  });
}
