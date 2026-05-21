import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:result_dart/result_dart.dart';

class ActiveConfigResolver {
  ActiveConfigResolver(
    this._repository,
    this._settingsStore,
  );

  final IAgentConfigRepository _repository;
  final IAppSettingsStore _settingsStore;

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
  }

  Future<void> clearActiveConfigId() async {
    await _settingsStore.remove(AppConstants.activeConfigIdSettingsKey);
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

    final result = metadataOnly
        ? await _repository.getByIdMetadata(normalized)
        : await _repository.getById(normalized);
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

    final nextConfig = configsResult
        .getOrThrow()
        .where((config) => config.id != normalized)
        .fold<Config?>(
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
