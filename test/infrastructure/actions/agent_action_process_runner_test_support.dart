import 'package:plug_agente/application/actions/action_environment_resolver.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_resolver.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/infrastructure/actions/action_process_stdin_setup.dart';

const ActionEnvironmentResolver kTestActionEnvironmentResolver = ActionEnvironmentResolver();

const AgentOperationalProfileResolver kTestAgentOperationalProfileResolver = AgentOperationalProfileResolver();

const ActionProcessStdinSetup kTestActionProcessStdinSetup = ActionProcessStdinSetup(
  secretPlaceholderResolver: AgentActionSecretPlaceholderResolver(),
);
