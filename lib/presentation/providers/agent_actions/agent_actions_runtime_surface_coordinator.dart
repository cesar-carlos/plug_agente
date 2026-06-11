import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_runtime_controller.dart';

/// Runtime settings surface: preflight, retention, maintenance, and elevated runner.
final class AgentActionsRuntimeSurfaceCoordinator {
  AgentActionsRuntimeSurfaceCoordinator({
    required AgentActionsRuntimeController runtimeController,
  }) : _runtimeController = runtimeController;

  final AgentActionsRuntimeController _runtimeController;

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

  Future<void> setMaintenanceMode({required bool enabled}) => _runtimeController.setMaintenanceMode(enabled: enabled);

  Future<void> setMaintenanceStrictMode({required bool enabled}) =>
      _runtimeController.setMaintenanceStrictMode(enabled: enabled);

  Future<void> prepareElevatedRunner() => _runtimeController.prepareElevatedRunner();

  bool isActionTypeUnavailable(AgentActionType type) => _runtimeController.isActionTypeUnavailable(type);

  bool allowsLocalManualOperation(AgentActionType actionType) =>
      _runtimeController.allowsLocalManualOperation(actionType);
}
