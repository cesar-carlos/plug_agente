import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_path_prod_defaults_constants.dart';
import 'package:plug_agente/domain/actions/action_policies.dart' show AgentActionEnvironmentPolicy;
import 'package:plug_agente/domain/actions/actions.dart' show AgentActionEnvironmentPolicy;
import 'package:plug_agente/domain/domain.dart' show AgentActionEnvironmentPolicy;

/// Resolves the agent operational profile used by [AgentActionEnvironmentPolicy].
class AgentOperationalProfileResolver {
  const AgentOperationalProfileResolver();

  String? get currentProfile {
    final raw = AppEnvironment.get(AgentActionGateConstants.operationalProfileEnvironmentKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    return raw.trim();
  }

  bool get isProductionProfile => AgentActionPathProdDefaultsConstants.isProductionProfile(currentProfile);
}
