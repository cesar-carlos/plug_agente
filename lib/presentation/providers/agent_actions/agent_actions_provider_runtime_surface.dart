part of '../agent_actions_provider.dart';

extension AgentActionsProviderRuntimeSurface on AgentActionsProvider {
  Future<void> savePreflightValidityDays(int days) => _runtimeSurfaceCoordinator.savePreflightValidityDays(days);

  Future<void> clearPreflightPersistedOverride() => _runtimeSurfaceCoordinator.clearPreflightPersistedOverride();

  Future<void> saveRetentionSettings({
    required int executionDays,
    required int remoteAuditDays,
    required int capturedOutputHours,
  }) => _runtimeSurfaceCoordinator.saveRetentionSettings(
    executionDays: executionDays,
    remoteAuditDays: remoteAuditDays,
    capturedOutputHours: capturedOutputHours,
  );

  Future<void> clearRetentionPersistedOverrides() => _runtimeSurfaceCoordinator.clearRetentionPersistedOverrides();

  Future<void> prepareElevatedRunner() => _runtimeSurfaceCoordinator.prepareElevatedRunner();

  Future<void> setMaintenanceMode({required bool enabled}) =>
      _runtimeSurfaceCoordinator.setMaintenanceMode(enabled: enabled);

  Future<void> setMaintenanceStrictMode({required bool enabled}) =>
      _runtimeSurfaceCoordinator.setMaintenanceStrictMode(enabled: enabled);

  bool isActionTypeUnavailable(AgentActionType type) => _runtimeSurfaceCoordinator.isActionTypeUnavailable(type);
}
