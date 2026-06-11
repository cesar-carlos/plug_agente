import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';

/// Short-TTL cache for active agent config metadata used on hot paths (e.g. DB streaming).
class ActiveConfigMetadataCache {
  ActiveConfigMetadataCache({
    ActiveConfigResolver? activeConfigResolver,
    IAgentConfigRepository? legacyRepository,
    Duration ttl = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _activeConfigResolver = activeConfigResolver,
       _legacyRepository = legacyRepository,
       _ttl = ttl,
       _clock = clock ?? DateTime.now;

  final ActiveConfigResolver? _activeConfigResolver;
  final IAgentConfigRepository? _legacyRepository;
  final Duration _ttl;
  final DateTime Function() _clock;

  Config? _cached;
  DateTime? _cachedAt;

  Future<Config?> resolveMetadata() async {
    final now = _clock();
    final cached = _cached;
    final cachedAt = _cachedAt;
    if (cached != null && cachedAt != null && now.difference(cachedAt) < _ttl) {
      return cached;
    }

    final resolved = await _loadMetadata();
    if (resolved != null) {
      _cached = resolved;
      _cachedAt = now;
    }
    return resolved;
  }

  void invalidate() {
    _cached = null;
    _cachedAt = null;
  }

  Future<Config?> _loadMetadata() async {
    final resolver = _activeConfigResolver;
    if (resolver != null) {
      return (await resolver.resolveActiveOrFallback(metadataOnly: true)).getOrNull();
    }
    final repository = _legacyRepository;
    if (repository != null) {
      return (await repository.getCurrentConfigMetadata()).getOrNull();
    }
    return null;
  }
}
