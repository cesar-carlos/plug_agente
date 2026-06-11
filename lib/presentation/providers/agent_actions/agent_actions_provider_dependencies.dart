import 'package:plug_agente/application/actions/i_action_command_safety_assessor.dart';
import 'package:plug_agente/application/ports/i_agent_actions_bundle_file_gateway.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/export_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/import_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_definitions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_triggers.dart';
import 'package:plug_agente/application/use_cases/list_developer_data7_connections.dart';
import 'package:plug_agente/application/use_cases/list_recent_agent_action_remote_audit.dart';
import 'package:plug_agente/application/use_cases/preview_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/slice_agent_action_captured_output.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart' show AgentActionsProvider;
import 'package:uuid/uuid.dart';

/// Use cases and services required to construct [AgentActionsProvider].
final class AgentActionsProviderDependencies {
  const AgentActionsProviderDependencies({
    required this.listDefinitions,
    required this.listExecutions,
    required this.saveDefinition,
    required this.deleteDefinition,
    required this.listTriggers,
    required this.deleteTrigger,
    required this.saveTrigger,
    required this.listDeveloperData7Connections,
    required this.runAction,
    required this.testDefinition,
    required this.previewDefinition,
    required this.cancelExecution,
    required this.getExecution,
    required this.sliceCapturedOutput,
    required this.listRecentRemoteAudit,
    required this.exportBundle,
    required this.importBundle,
    required this.featureFlags,
    required this.uuid,
    required this.commandSafetyAssessor,
    required this.retentionSettings,
    required this.bundleFileGateway,
    this.saveAgentActionSecret,
    this.deleteAgentActionSecret,
  });

  final ListAgentActionDefinitions listDefinitions;
  final ListAgentActionExecutions listExecutions;
  final SaveAgentActionDefinition saveDefinition;
  final DeleteAgentActionDefinition deleteDefinition;
  final ListAgentActionTriggers listTriggers;
  final DeleteAgentActionTrigger deleteTrigger;
  final SaveAgentActionTrigger saveTrigger;
  final ListDeveloperData7Connections listDeveloperData7Connections;
  final RunAgentActionLocally runAction;
  final TestAgentActionDefinition testDefinition;
  final PreviewAgentActionDefinition previewDefinition;
  final CancelAgentActionExecution cancelExecution;
  final GetAgentActionExecution getExecution;
  final SliceAgentActionCapturedOutput sliceCapturedOutput;
  final ListRecentAgentActionRemoteAudit listRecentRemoteAudit;
  final ExportAgentActionsBundle exportBundle;
  final ImportAgentActionsBundle importBundle;
  final FeatureFlags featureFlags;
  final Uuid uuid;
  final IActionCommandSafetyAssessor commandSafetyAssessor;
  final AgentActionRetentionSettings retentionSettings;
  final IAgentActionsBundleFileGateway bundleFileGateway;
  final SaveAgentActionSecret? saveAgentActionSecret;
  final DeleteAgentActionSecret? deleteAgentActionSecret;
}
