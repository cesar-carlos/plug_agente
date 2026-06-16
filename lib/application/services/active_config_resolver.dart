import 'package:plug_agente/application/services/active_config_metadata_cache.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_odbc_circuit_breaker_reset.dart';
import 'package:plug_agente/domain/repositories/i_query_config_source.dart';
import 'package:result_dart/result_dart.dart';

class ActiveConfigResolver implements IQueryConfigSource {
  ActiveConfigResolver(
    this._repository,
    this._settingsStore, {
    IOdbcCircuitBreakerReset? circuitBreakerReset,
    IOdbcCircuitBreakerReset? Function()? circuitBreakerResetProvider,
    ActiveConfigMetadataCache? metadataCache,
  }) : _circuitBreakerReset = circuitBreakerReset,
       _circuitBreakerResetProvider = circuitBreakerResetProvider,
       _metadataCache = metadataCache;

  final IAgentConfigRepository _repository;
  final IAppSettingsStore _settingsStore;
  final IOdbcCircuitBreakerReset? _circuitBreakerReset;
  final IOdbcCircuitBreakerReset? Function()? _circuitBreakerResetProvider;
  final ActiveConfigMetadataCache? _metadataCache;

  IOdbcCircuitBreakerReset? get _resolvedCircuitBreakerReset =>
      _circuitBreakerReset ?? _circuitBreakerResetProvider?.call();

  @override
  Future<Result<Config>> resolveConfigForQuery(String? configId) {
    final normalized = _normalizeConfigId(configId);
    if (normalized != null) {
      return resolveExplicit(normalized);
    }
    return resolveActiveForDatabaseAccess();
  }

  @override
  Future<Result<Config>> resolveActiveConfig() {
    return resolveActiveForDatabaseAccess();
  }

  Future<Result<Config>> resolveActiveForDatabaseAccess() {
    return resolveActiveOrFallback();
  }

  String? getActiveConfigId() => _normalizeConfigId(
    _settingsStore.getString(AppConstants.activeConfigIdSettingsKey),
  );

  Future<void> setActiveConfigId(String configId) async {
    final normalized = _normalizeConfigId(configId);
    if (normalized == null) {
      return;
    }
    if (normalized == getActiveConfigId()) {
      return;
    }
    await _settingsStore.setString(
      AppConstants.activeConfigIdSettingsKey,
      normalized,
    );
    _metadataCache?.invalidate();
    final configResult = await _repository.getById(normalized);
    if (configResult.isSuccess()) {
      _resolvedCircuitBreakerReset?.resetForConfig(configResult.getOrThrow());
    }
  }

  Future<void> clearActiveConfigId() async {
    await _settingsStore.remove(AppConstants.activeConfigIdSettingsKey);
    _metadataCache?.invalidate();
  }

  Future<Result<Config>> resolveExplicit(
    String configId, {
    bool metadataOnly = false,
    bool setActiveOnSuccess = false,
  }) async {
    final normalized = _normalizeConfigId(configId);
    if (normalized == null) {
      return Failure(
        domain.ConfigurationFailure('Config ID is required'),
      );
    }

    final result = metadataOnly ? await _repository.getByIdMetadata(normalized) : await _repository.getById(normalized);
    if (setActiveOnSuccess && result.isSuccess()) {
      await setActiveConfigId(normalized);
    }
    return result;
  }

  Future<Result<Config>> resolveActiveOrFallback({
    bool metadataOnly = false,
    bool persistFallback = true,
  }) async {
    final activeConfigId = getActiveConfigId();
    if (activeConfigId != null) {
      final activeResult = metadataOnly
          ? await _repository.getByIdMetadata(activeConfigId)
          : await _repository.getById(activeConfigId);
      if (activeResult.isSuccess()) {
        return activeResult;
      }

      final failure = activeResult.exceptionOrNull();
      if (failure is! domain.NotFoundFailure) {
        return Failure(failure!);
      }
      await clearActiveConfigId();
    }

    final fallbackResult = metadataOnly
        ? await _repository.getCurrentConfigMetadata()
        : await _repository.getCurrentConfig();
    if (persistFallback && fallbackResult.isSuccess()) {
      await setActiveConfigId(fallbackResult.getOrThrow().id);
    }
    return fallbackResult;
  }

  Future<void> handleDeletedConfig(String configId) async {
    final normalized = _normalizeConfigId(configId);
    if (normalized == null || normalized != getActiveConfigId()) {
      return;
    }

    final configsResult = await _repository.getAllMetadata();
    if (configsResult.isError()) {
      await clearActiveConfigId();
      return;
    }

    final nextConfig = configsResult.getOrThrow().where((config) => config.id != normalized).fold<Config?>(
      null,
      (current, config) {
        if (current == null || config.updatedAt.isAfter(current.updatedAt)) {
          return config;
        }
        return current;
      },
    );

    if (nextConfig == null) {
      await clearActiveConfigId();
      return;
    }

    await setActiveConfigId(nextConfig.id);
  }

  String? _normalizeConfigId(String? configId) {
    final normalized = configId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
