import 'dart:async';

import 'package:plug_agente/application/use_cases/import_agent_actions_bundle.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_bundle_transfer_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_definitions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_remote_audit_controller.dart';

/// Selection changes and run/test/cancel/bundle operations for agent actions UI.
final class AgentActionsSelectionCoordinator {
  AgentActionsSelectionCoordinator({
    required AgentActionsDefinitionsController definitionsController,
    required AgentActionsExecutionsController executionsController,
    required AgentActionsRemoteAuditController remoteAuditController,
    required AgentActionsBundleTransferController bundleTransferController,
    required void Function() notifyStateChanged,
    required void Function(String? message) setErrorMessage,
    required Future<void> Function() reload,
    required Future<void> Function() syncTriggersForSelection,
    required Future<void> Function() refreshSelectedSecretReport,
    required AgentActionDefinition? Function() selectedDefinition,
    required bool Function() canDeleteSelected,
    required bool Function() canRunSelected,
    required bool Function() canTestSelected,
    required bool Function(AgentActionExecution execution) canCancelExecution,
    required bool Function() canTransferBundle,
  }) : _definitionsController = definitionsController,
       _executionsController = executionsController,
       _remoteAuditController = remoteAuditController,
       _bundleTransferController = bundleTransferController,
       _notifyStateChanged = notifyStateChanged,
       _setErrorMessage = setErrorMessage,
       _reload = reload,
       _syncTriggersForSelection = syncTriggersForSelection,
       _refreshSelectedSecretReport = refreshSelectedSecretReport,
       _selectedDefinition = selectedDefinition,
       _canDeleteSelected = canDeleteSelected,
       _canRunSelected = canRunSelected,
       _canTestSelected = canTestSelected,
       _canCancelExecution = canCancelExecution,
       _canTransferBundle = canTransferBundle;

  final AgentActionsDefinitionsController _definitionsController;
  final AgentActionsExecutionsController _executionsController;
  final AgentActionsRemoteAuditController _remoteAuditController;
  final AgentActionsBundleTransferController _bundleTransferController;
  final void Function() _notifyStateChanged;
  final void Function(String? message) _setErrorMessage;
  final Future<void> Function() _reload;
  final Future<void> Function() _syncTriggersForSelection;
  final Future<void> Function() _refreshSelectedSecretReport;
  final AgentActionDefinition? Function() _selectedDefinition;
  final bool Function() _canDeleteSelected;
  final bool Function() _canRunSelected;
  final bool Function() _canTestSelected;
  final bool Function(AgentActionExecution execution) _canCancelExecution;
  final bool Function() _canTransferBundle;

  void selectAction(String actionId) {
    if (_definitionsController.selectedActionId == actionId) {
      return;
    }

    _remoteAuditController.clearCorrelation();
    _definitionsController.selectAction(actionId);
    if (_executionsController.lastTestedActionId != actionId) {
      _executionsController.clearTestStateForSelectionChange();
    }
    _notifyStateChanged();
    unawaited(_syncTriggersForSelection());
    unawaited(_refreshSelectedSecretReport());
  }

  Future<void> deleteSelectedAction() async {
    final definition = _selectedDefinition();
    if (definition == null || !_canDeleteSelected()) {
      return;
    }

    _setErrorMessage(null);
    _executionsController.clearTestStateForSelectionChange();
    final outcome = await _definitionsController.deleteSelectedAction(
      definition: definition,
      canDelete: _canDeleteSelected(),
    );

    if (outcome.shouldReload) {
      await _reload();
      return;
    }

    if (outcome.errorMessage != null) {
      _setErrorMessage(outcome.errorMessage);
      _notifyStateChanged();
    }
  }

  Future<bool> exportBundleToFile(String filePath, {required AppLocalizations l10n}) async {
    _setErrorMessage(null);
    final outcome = await _bundleTransferController.exportToFile(
      filePath: filePath,
      l10n: l10n,
      canTransfer: _canTransferBundle(),
    );
    if (outcome.errorMessage != null) {
      _setErrorMessage(outcome.errorMessage);
      _notifyStateChanged();
    }
    return outcome.succeeded;
  }

  Future<ImportAgentActionsBundleSummary?> importBundleFromFile(
    String filePath, {
    required AppLocalizations l10n,
  }) async {
    _setErrorMessage(null);
    final outcome = await _bundleTransferController.importFromFile(
      filePath: filePath,
      l10n: l10n,
      canTransfer: _canTransferBundle(),
    );
    if (outcome.errorMessage != null) {
      _setErrorMessage(outcome.errorMessage);
      _notifyStateChanged();
      return null;
    }

    final summary = outcome.summary;
    if (summary != null) {
      await _reload();
    }
    return summary;
  }

  Future<void> runSelectedAction({bool dangerousCommandConfirmed = false}) async {
    final definition = _selectedDefinition();
    if (definition == null || !_canRunSelected()) {
      return;
    }

    _setErrorMessage(null);
    final errorMessage = await _executionsController.runAction(
      definition: definition,
      dangerousCommandConfirmed: dangerousCommandConfirmed,
    );
    if (errorMessage != null) {
      _setErrorMessage(errorMessage);
      _notifyStateChanged();
      return;
    }

    await _reload();
  }

  Future<void> testSelectedAction() async {
    final definition = _selectedDefinition();
    if (definition == null || !_canTestSelected()) {
      return;
    }

    _setErrorMessage(null);
    final outcome = await _executionsController.testAction(
      definition: definition,
      onPreflightSuccess: (testedDefinition) async {
        final errorMessage = await _definitionsController.recordPreflightSuccess(testedDefinition);
        if (errorMessage != null) {
          _setErrorMessage(errorMessage);
        }
      },
      onPreflightFailure: _definitionsController.clearPreflightSessionForDefinition,
    );

    if (outcome.errorMessage != null) {
      _setErrorMessage(outcome.errorMessage);
    }
  }

  Future<void> cancelExecution(AgentActionExecution execution) async {
    if (!_canCancelExecution(execution)) {
      return;
    }

    _setErrorMessage(null);
    final errorMessage = await _executionsController.cancelExecution(execution);
    if (errorMessage != null) {
      _setErrorMessage(errorMessage);
      _notifyStateChanged();
      return;
    }

    await _reload();
  }
}
