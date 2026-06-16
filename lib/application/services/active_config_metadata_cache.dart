import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_active_config_query_cache.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';

class _TimedConfigEntry {
  const _TimedConfigEntry({required this.config, required this.cachedAt});

  final Config config;
  final DateTime cachedAt;
}

/// Short-TTL cache for active agent config metadata used on hot paths (e.g. DB streaming).
class ActiveConfigMetadataCache implements IActiveConfigQueryCache {
  ActiveConfigMetadataCache({
    ActiveConfigResolver? activeConfigResolver,
    ActiveConfigResolver Function()? activeConfigResolverProvider,
    IAgentConfigRepository? legacyRepository,
    Duration ttl = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _activeConfigResolver = activeConfigResolver,
       _activeConfigResolverProvider = activeConfigResolverProvider,
       _legacyRepository = legacyRepository,
       _ttl = ttl,
       _clock = clock ?? DateTime.now;

  static const String _activeConfigCacheKey = '__active__';

  final ActiveConfigResolver? _activeConfigResolver;
  final ActiveConfigResolver Function()? _activeConfigResolverProvider;
  final IAgentConfigRepository? _legacyRepository;
  final Duration _ttl;
  final DateTime Function() _clock;

  Config? _metadataCached;
  DateTime? _metadataCachedAt;
  final Map<String, _TimedConfigEntry> _databaseAccessCache = {};

  Future<Config?> resolveMetadata() async {
    final now = _clock();
    final cached = _metadataCached;
    final cachedAt = _metadataCachedAt;
    if (cached != null && cachedAt != null && now.difference(cachedAt) < _ttl) {
      return cached;
    }

    final resolved = await _loadMetadata();
    if (resolved != null) {
      _metadataCached = resolved;
      _metadataCachedAt = now;
    }
    return resolved;
  }

  @override
  Future<Config?> resolveForDatabaseAccess({String? configId}) async {
    final cacheKey = _databaseAccessCacheKey(configId);
    final now = _clock();
    final cached = _databaseAccessCache[cacheKey];
    if (cached != null && now.difference(cached.cachedAt) < _ttl) {
      return cached.config;
    }

    final resolved = await _loadForDatabaseAccess(configId);
    if (resolved != null) {
      _databaseAccessCache[cacheKey] = _TimedConfigEntry(
        config: resolved,
        cachedAt: now,
      );
    }
    return resolved;
  }

  @override
  void invalidate() {
    _metadataCached = null;
    _metadataCachedAt = null;
    _databaseAccessCache.clear();
  }

  Future<Config?> _loadMetadata() async {
    final resolver = _activeConfigResolver ?? _activeConfigResolverProvider?.call();
    if (resolver != null) {
      return (await resolver.resolveActiveOrFallback(metadataOnly: true)).getOrNull();
    }
    final repository = _legacyRepository;
    if (repository != null) {
      return (await repository.getCurrentConfigMetadata()).getOrNull();
    }
    return null;
  }

  Future<Config?> _loadForDatabaseAccess(String? configId) async {
    final resolver = _activeConfigResolver ?? _activeConfigResolverProvider?.call();
    if (resolver != null) {
      final normalized = configId?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        return (await resolver.resolveExplicit(normalized)).getOrNull();
      }
      return (await resolver.resolveActiveForDatabaseAccess()).getOrNull();
    }

    final repository = _legacyRepository;
    if (repository == null) {
      return null;
    }

    final normalized = configId?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return (await repository.getById(normalized)).getOrNull();
    }
    return (await repository.getCurrentConfig()).getOrNull();
  }

  String _databaseAccessCacheKey(String? configId) {
    final normalized = configId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return _activeConfigCacheKey;
    }
    return normalized;
  }
}
