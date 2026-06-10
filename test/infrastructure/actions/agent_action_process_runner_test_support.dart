import 'package:plug_agente/application/actions/action_environment_resolver.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_resolver.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/domain/actions/action_adapter_registry.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/action_process_stdin_setup.dart';
import 'package:plug_agente/infrastructure/actions/command_line_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/executable_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/jar_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/script_action_adapter.dart';

const ActionEnvironmentResolver kTestActionEnvironmentResolver = ActionEnvironmentResolver();

const AgentOperationalProfileResolver kTestAgentOperationalProfileResolver = AgentOperationalProfileResolver();

const ActionProcessStdinSetup kTestActionProcessStdinSetup = ActionProcessStdinSetup(
  secretPlaceholderResolver: AgentActionSecretPlaceholderResolver(),
);

AgentActionAdapterRegistry createTestAdapterRegistry({
  required ActionPathValidator pathValidator,
  ActionCommandNormalizer commandNormalizer = const ActionCommandNormalizer(),
}) {
  return AgentActionAdapterRegistry([
    CommandLineActionAdapter(
      commandNormalizer: commandNormalizer,
      pathValidator: pathValidator,
    ),
    ExecutableActionAdapter(
      commandNormalizer: commandNormalizer,
      pathValidator: pathValidator,
    ),
    ScriptActionAdapter(
      commandNormalizer: commandNormalizer,
      pathValidator: pathValidator,
    ),
    JarActionAdapter(
      commandNormalizer: commandNormalizer,
      pathValidator: pathValidator,
    ),
  ]);
}
