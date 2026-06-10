import 'package:plug_agente/domain/actions/actions.dart';

typedef AgentActionPathExists = Future<bool> Function(String path);
typedef AgentActionPathCanonicalizer = Future<String> Function(String path);
typedef AgentActionFileLengthResolver = Future<int> Function(String path);
typedef AgentActionFileTextReader = Future<String> Function(String path);
typedef AgentActionLaunchAccessValidator =
    ActionValidationFailure? Function({
      required String actionId,
      required String field,
      required String path,
      required String phase,
    });

typedef AgentActionProductionProfileResolver = bool Function();

class AgentActionValidatedPath {
  const AgentActionValidatedPath({
    required this.originalPath,
    required this.canonicalPath,
    this.sizeBytes,
    this.lastModifiedUtc,
    this.contentHash,
  });

  final String originalPath;
  final String canonicalPath;
  final int? sizeBytes;
  final DateTime? lastModifiedUtc;
  final String? contentHash;
}

class AgentActionPathValidation {
  const AgentActionPathValidation({
    this.path,
  });

  const AgentActionPathValidation.notProvided() : path = null;

  final AgentActionValidatedPath? path;

  bool get hasPath => path != null;
}

class PathSnapshotCheck {
  const PathSnapshotCheck.unchanged() : warningMessage = null;

  const PathSnapshotCheck.warning(this.warningMessage);

  final String? warningMessage;

  bool get hasWarning => warningMessage != null && warningMessage!.isNotEmpty;
}
