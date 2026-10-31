part of '../agent_actions_provider.dart';

extension AgentActionsProviderRuntimeSurface on AgentActionsProvider {
  Future<void> saveRemoteAccess({required bool remote, required bool io, bool? adHoc}) =>
      _runtimeController.saveRemoteAccess(remote: remote, io: io, adHoc: adHoc);

  Future<void> savePreflightValidityDays(int days) => _runtimeController.savePreflightValidityDays(days);

  Future<void> clearPreflightPersistedOverride() => _runtimeController.clearPreflightPersistedOverride();

  Future<void> saveRetentionSettings({
    required int executionDays,
    required int remoteAuditDays,
    required int capturedOutputHours,
  }) => _runtimeController.saveRetentionSettings(
    executionDays: executionDays,
    remoteAuditDays: remoteAuditDays,
    capturedOutputHours: capturedOutputHours,
  );

  Future<void> clearRetentionPersistedOverrides() => _runtimeController.clearRetentionPersistedOverrides();

  Future<void> prepareElevatedRunner() => _runtimeController.prepareElevatedRunner();

  Future<void> setMaintenanceMode({required bool enabled}) => _runtimeController.setMaintenanceMode(enabled: enabled);

  Future<void> setMaintenanceStrictMode({required bool enabled}) =>
      _runtimeController.setMaintenanceStrictMode(enabled: enabled);

  bool isActionTypeUnavailable(AgentActionType type) => _runtimeController.isActionTypeUnavailable(type);
}
