/// Reads agent-action homologation test path manifests from `tool/*.txt`.
library;

import 'dart:io';

const String agentActionsContractTestPathsFileName = 'agent_actions_contract_test_paths.txt';
const String agentActionsUiTestPathsFileName = 'agent_actions_ui_test_paths.txt';

/// Walks up from [startDirectory] until `pubspec.yaml` and the contract manifest exist.
String resolvePlugAgenteProjectRoot({String? startDirectory}) {
  var directory = Directory(startDirectory ?? File(Platform.script.toFilePath()).parent.path);
  while (true) {
    final pubspec = File('${directory.path}${Platform.pathSeparator}pubspec.yaml');
    final manifest = File(
      '${directory.path}${Platform.pathSeparator}tool${Platform.pathSeparator}$agentActionsContractTestPathsFileName',
    );
    if (pubspec.existsSync() && manifest.existsSync()) {
      return directory.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('plug_agente project root not found from ${directory.path}');
    }
    directory = parent;
  }
}

List<String> readAgentActionTestManifest(
  String projectRoot,
  String fileName,
) {
  final file = File('$projectRoot${Platform.pathSeparator}tool${Platform.pathSeparator}$fileName');
  if (!file.existsSync()) {
    throw StateError('Missing test manifest: ${file.path}');
  }
  return file
      .readAsLinesSync()
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty && !line.startsWith('#'))
      .toList(growable: false);
}

List<String> readAgentActionContractTestPaths(String projectRoot) =>
    readAgentActionTestManifest(projectRoot, agentActionsContractTestPathsFileName);

List<String> readAgentActionUiTestPaths(String projectRoot) =>
    readAgentActionTestManifest(projectRoot, agentActionsUiTestPathsFileName);
