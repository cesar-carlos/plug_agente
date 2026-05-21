import 'package:plug_agente/application/actions/agent_action_secret_placeholder_scanner.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';

class AgentActionSecretAvailabilityReport {
  const AgentActionSecretAvailabilityReport({
    required this.referencedSecretNames,
    this.missingSecretNames = const <String>{},
    this.storeAvailable = false,
  });

  final Set<String> referencedSecretNames;
  final Set<String> missingSecretNames;
  final bool storeAvailable;

  bool get hasReferencedSecrets => referencedSecretNames.isNotEmpty;

  bool get hasMissingSecrets => missingSecretNames.isNotEmpty;
}

class AgentActionSecretAvailabilityChecker {
  const AgentActionSecretAvailabilityChecker({
    IAgentActionSecretStore? secretStore,
  }) : _secretStore = secretStore;

  final IAgentActionSecretStore? _secretStore;

  Future<AgentActionSecretAvailabilityReport> check(AgentActionDefinition definition) async {
    final referenced = AgentActionSecretPlaceholderScanner.collectFromDefinition(definition);
    final store = _secretStore;
    if (store == null || !store.isAvailable || referenced.isEmpty) {
      return AgentActionSecretAvailabilityReport(
        referencedSecretNames: referenced,
        storeAvailable: store?.isAvailable ?? false,
      );
    }

    final missing = <String>{};
    for (final name in referenced) {
      if (!await store.exists(name)) {
        missing.add(name);
      }
    }

    return AgentActionSecretAvailabilityReport(
      referencedSecretNames: referenced,
      missingSecretNames: Set<String>.unmodifiable(missing),
      storeAvailable: true,
    );
  }
}
