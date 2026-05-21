import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';

class AgentRegisterProfileProvider {
  AgentRegisterProfileProvider({
    ActiveConfigResolver? activeConfigResolver,
    IAgentConfigRepository? configRepository,
    Duration cacheTtl = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _activeConfigResolver = activeConfigResolver,
       _configRepository = configRepository,
       _cacheTtl = cacheTtl,
       _now = now ?? DateTime.now;

  final ActiveConfigResolver? _activeConfigResolver;
  final IAgentConfigRepository? _configRepository;
  final Duration _cacheTtl;
  final DateTime Function() _now;
  Future<Map<String, dynamic>?>? _pendingSnapshot;
  Map<String, dynamic>? _cachedSnapshot;
  DateTime? _cachedSnapshotExpiresAt;
  String? _cachedConfigId;

  Future<Map<String, dynamic>?> loadSnapshot() {
    final pending = _pendingSnapshot;
    if (pending != null) {
      return pending;
    }

    final activeConfigId = _activeConfigResolver?.getActiveConfigId();
    if (_activeConfigResolver != null && _cachedConfigId != activeConfigId) {
      clearCache();
    }

    final cachedSnapshot = _cachedSnapshot;
    final cachedSnapshotExpiresAt = _cachedSnapshotExpiresAt;
    if (cachedSnapshot != null && cachedSnapshotExpiresAt != null && cachedSnapshotExpiresAt.isAfter(_now())) {
      return Future.value(cachedSnapshot);
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
    final resolver = _activeConfigResolver;
    final repository = _configRepository;
    if (resolver == null && repository == null) {
      return null;
    }
    final result = resolver != null
        ? await resolver.resolveActiveOrFallback(
            metadataOnly: true,
          )
        : await repository!.getCurrentConfigMetadata();
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
    final snapshot = <String, dynamic>{
      'profile': profileResult.getOrThrow().toJson(),
      'profile_version': ?config.hubProfileVersion,
      'profile_updated_at': ?hubUpdatedAt,
    };
    if (_cacheTtl > Duration.zero) {
      _cachedSnapshot = snapshot;
      _cachedSnapshotExpiresAt = _now().add(_cacheTtl);
      _cachedConfigId = config.id;
    }
    return snapshot;
  }

  void clearCache() {
    _cachedSnapshot = null;
    _cachedSnapshotExpiresAt = null;
    _cachedConfigId = null;
  }
}
