import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';

class AgentRegisterProfileProvider {
  AgentRegisterProfileProvider({
    required IAgentConfigRepository configRepository,
  }) : _configRepository = configRepository;

  final IAgentConfigRepository _configRepository;
  Future<Map<String, dynamic>?>? _pendingSnapshot;

  Future<Map<String, dynamic>?> loadSnapshot() {
    final pending = _pendingSnapshot;
    if (pending != null) {
      return pending;
    }

    final snapshot = _loadSnapshot();
    _pendingSnapshot = snapshot;
    snapshot.whenComplete(() {
      if (identical(_pendingSnapshot, snapshot)) {
        _pendingSnapshot = null;
      }
    });
    return snapshot;
  }

  Future<Map<String, dynamic>?> _loadSnapshot() async {
    final result = await _configRepository.getCurrentConfig();
    if (result.isError()) {
      return null;
    }
    final config = result.getOrThrow();
    final profileResult = AgentProfile.fromConfig(config);
    if (profileResult.isError()) {
      return null;
    }

    final hubUpdatedAt = config.hubProfileVersion != null
        ? DateTime.tryParse(config.hubProfileUpdatedAt ?? '')?.toUtc().toIso8601String()
        : null;
    return <String, dynamic>{
      'profile': profileResult.getOrThrow().toJson(),
      'profile_version': ?config.hubProfileVersion,
      'profile_updated_at': ?hubUpdatedAt,
    };
  }
}
