import 'package:plug_agente/application/ports/i_agent_actions_bundle_file_gateway.dart';
import 'package:plug_agente/application/use_cases/export_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/import_agent_actions_bundle.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

typedef AgentActionsBundleTransferStateChanged = void Function();

class AgentActionsBundleTransferController {
  AgentActionsBundleTransferController({
    required ExportAgentActionsBundle exportBundle,
    required ImportAgentActionsBundle importBundle,
    required IAgentActionsBundleFileGateway bundleFileGateway,
    required String Function(Exception failure) messageFor,
    required AgentActionsBundleTransferStateChanged onStateChanged,
  }) : _exportBundle = exportBundle,
       _importBundle = importBundle,
       _bundleFileGateway = bundleFileGateway,
       _messageFor = messageFor,
       _onStateChanged = onStateChanged;

  final ExportAgentActionsBundle _exportBundle;
  final ImportAgentActionsBundle _importBundle;
  final IAgentActionsBundleFileGateway _bundleFileGateway;
  final String Function(Exception failure) _messageFor;
  final AgentActionsBundleTransferStateChanged _onStateChanged;

  bool isTransferring = false;

  Future<({bool succeeded, String? errorMessage})> exportToFile({
    required String filePath,
    required AppLocalizations l10n,
    required bool canTransfer,
  }) async {
    if (!canTransfer) {
      return (succeeded: false, errorMessage: null);
    }

    isTransferring = true;
    _onStateChanged();

    final result = await _exportBundle();
    if (result.isError()) {
      isTransferring = false;
      final errorMessage = _messageFor(result.exceptionOrNull()!);
      _onStateChanged();
      return (succeeded: false, errorMessage: errorMessage);
    }

    final writeResult = await _bundleFileGateway.writeText(filePath, result.getOrThrow());
    if (writeResult.isError()) {
      isTransferring = false;
      _onStateChanged();
      return (succeeded: false, errorMessage: l10n.agentActionsBundleExportWriteFailed);
    }

    isTransferring = false;
    _onStateChanged();
    return (succeeded: true, errorMessage: null);
  }

  Future<({ImportAgentActionsBundleSummary? summary, String? errorMessage})> importFromFile({
    required String filePath,
    required AppLocalizations l10n,
    required bool canTransfer,
  }) async {
    if (!canTransfer) {
      return (summary: null, errorMessage: null);
    }

    isTransferring = true;
    _onStateChanged();

    final readResult = await _bundleFileGateway.readText(filePath);
    if (readResult.isError()) {
      isTransferring = false;
      _onStateChanged();
      return (summary: null, errorMessage: l10n.agentActionsBundleImportReadFailed);
    }

    final payload = readResult.getOrThrow();

    final result = await _importBundle(payload);
    if (result.isError()) {
      isTransferring = false;
      final errorMessage = _messageFor(result.exceptionOrNull()!);
      _onStateChanged();
      return (summary: null, errorMessage: errorMessage);
    }

    isTransferring = false;
    _onStateChanged();
    return (summary: result.getOrThrow(), errorMessage: null);
  }
}
