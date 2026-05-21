import 'package:plug_agente/domain/actions/action_path_reference.dart';
import 'package:plug_agente/domain/actions/action_policies.dart';

class DeveloperData7ConnectionLookupRequest {
  const DeveloperData7ConnectionLookupRequest({
    required this.actionId,
    required this.data7ConfigPath,
    this.pathPolicy = const AgentActionPathPolicy(),
    this.selectedConnectionId,
  });

  final String actionId;
  final AgentActionPathReference data7ConfigPath;
  final AgentActionPathPolicy pathPolicy;
  final String? selectedConnectionId;
}

class DeveloperData7ConnectionOption {
  const DeveloperData7ConnectionOption({
    required this.id,
    required this.label,
    required this.snapshotHash,
  });

  final String id;
  final String label;
  final String snapshotHash;
}

class DeveloperData7ConnectionLookupResult {
  const DeveloperData7ConnectionLookupResult({
    required this.resolvedConfigPath,
    required this.usedDefaultLocation,
    required this.connections,
    this.selectedConnectionId,
  });

  final AgentActionPathReference resolvedConfigPath;
  final bool usedDefaultLocation;
  final List<DeveloperData7ConnectionOption> connections;
  final String? selectedConnectionId;
}
