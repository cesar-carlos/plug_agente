import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_risk_labels.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('should include runner unavailable descriptor when runner is degraded', () {
    const definition = AgentActionDefinition(
      id: 'action-1',
      name: 'Run',
      config: CommandLineActionConfig(command: 'dir'),
    );

    final descriptors = collectAgentActionRiskDescriptors(
      definition: definition,
      l10n: l10n,
      runnerUnavailable: true,
    );

    expect(
      descriptors.map((descriptor) => descriptor.label),
      contains(l10n.agentActionsRiskRunnerUnavailable),
    );
  });

  test('should include elevated descriptor when policy requests elevated run', () {
    const definition = AgentActionDefinition(
      id: 'action-elevated',
      name: 'Elevated',
      config: CommandLineActionConfig(command: 'whoami'),
      policies: AgentActionDefinitionPolicies(
        elevated: AgentActionElevatedPolicy(runElevated: true),
      ),
    );

    final descriptors = collectAgentActionRiskDescriptors(
      definition: definition,
      l10n: l10n,
    );

    expect(
      descriptors.map((descriptor) => descriptor.label),
      contains(l10n.agentActionsRiskElevated),
    );
  });
}
