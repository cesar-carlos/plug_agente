part of '../agent_actions_provider.dart';

Future<bool> exportBundleToFileFor(AgentActionsProvider provider, String filePath) async {
  if (!provider.canTransferBundle) {
    return false;
  }

  final selectedId = provider._selectedActionId;
  final actionIds = selectedId == null ? null : <String>[selectedId];

  provider._isTransferringBundle = true;
  provider._errorMessage = null;
  provider.notifyListeners();

  final result = await provider._exportBundle(actionIds: actionIds);
  if (result.isError()) {
    provider._isTransferringBundle = false;
    provider._errorMessage = provider._messageFor(result.exceptionOrNull()!);
    provider.notifyListeners();
    return false;
  }

  final writeResult = await provider._bundleFileGateway.writeText(filePath, result.getOrThrow());
  if (writeResult.isError()) {
    provider._isTransferringBundle = false;
    provider._errorMessage =
        lookupAppLocalizations(PlatformDispatcher.instance.locale).agentActionsBundleExportWriteFailed;
    provider.notifyListeners();
    return false;
  }

  provider._isTransferringBundle = false;
  provider.notifyListeners();
  return true;
}

Future<ImportAgentActionsBundleSummary?> importBundleFromFileFor(
  AgentActionsProvider provider,
  String filePath,
) async {
  if (!provider.canTransferBundle) {
    return null;
  }

  provider._isTransferringBundle = true;
  provider._errorMessage = null;
  provider.notifyListeners();

  final readResult = await provider._bundleFileGateway.readText(filePath);
  if (readResult.isError()) {
    provider._isTransferringBundle = false;
    provider._errorMessage =
        lookupAppLocalizations(PlatformDispatcher.instance.locale).agentActionsBundleImportReadFailed;
    provider.notifyListeners();
    return null;
  }

  final payload = readResult.getOrThrow();

  final result = await provider._importBundle(payload);
  if (result.isError()) {
    provider._isTransferringBundle = false;
    provider._errorMessage = provider._messageFor(result.exceptionOrNull()!);
    provider.notifyListeners();
    return null;
  }

  final summary = result.getOrThrow();
  provider._isTransferringBundle = false;
  await provider.load();
  return summary;
}
