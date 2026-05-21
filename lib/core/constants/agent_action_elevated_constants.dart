import 'package:path/path.dart' as p;

/// Paths and marker names for the Windows elevated action runner bridge (Fase 5).
abstract final class AgentActionElevatedConstants {
  static const String elevatedSubdirectoryName = 'agent_actions/elevated';
  static const String requestsSubdirectoryName = '$elevatedSubdirectoryName/requests';
  static const String statusSubdirectoryName = '$elevatedSubdirectoryName/status';
  static const String cancelSubdirectoryName = '$elevatedSubdirectoryName/cancel';
  static const String materializedSubdirectoryName = '$elevatedSubdirectoryName/materialized';

  static const int requestSchemaVersion = 1;
  static const int statusSchemaVersion = 1;
  static const int cancelSchemaVersion = 1;
  static const int materializedSchemaVersion = 1;

  /// Written by the elevated helper installer when the scheduled task is ready.
  static const String readyMarkerFileName = 'elevated_runner.ready';

  /// Windows scheduled task name registered by the elevated helper installer.
  static const String scheduledTaskName = r'PlugAgente\ElevatedActionRunner';

  static const String helperExecutableEnvKey = 'ELEVATED_ACTION_RUNNER_EXE';

  static const String defaultHelperExecutableName = 'plug_agente_elevated_runner.exe';

  static const String helperWatchRequestsArgument = '--watch-requests';

  static const Duration requestTtl = Duration(minutes: 5);
  static const Duration statusPollInterval = Duration(milliseconds: 500);

  /// Wall-clock interval for purging stale elevated bridge artifact files.
  static const Duration bridgeArtifactPurgeInterval = Duration(minutes: 15);

  /// Max age for elevated request/status/materialized/cancel files kept on disk.
  static Duration get bridgeArtifactMaxAge => requestTtl + requestTtl;

  static const Set<String> supportedElevatedActionTypeNames = <String>{
    'commandLine',
    'developer',
  };

  /// Helper status failure codes that indicate the elevated runner should be marked degraded.
  static const Set<String> helperDegradedFailureCodes = <String>{
    'ACTION_ELEVATED_REQUEST_PROTECTION_FAILED',
    'ACTION_RUNTIME_ERROR',
  };

  static String readyMarkerPath(String appDirectoryPath) {
    return p.join(appDirectoryPath, elevatedSubdirectoryName, readyMarkerFileName);
  }

  static String requestsDirectoryPath(String appDirectoryPath) {
    return p.join(appDirectoryPath, requestsSubdirectoryName);
  }

  static String statusDirectoryPath(String appDirectoryPath) {
    return p.join(appDirectoryPath, statusSubdirectoryName);
  }

  static String requestFilePath(String appDirectoryPath, String executionId) {
    return p.join(requestsDirectoryPath(appDirectoryPath), '$executionId.json');
  }

  static String statusFilePath(String appDirectoryPath, String executionId) {
    return p.join(statusDirectoryPath(appDirectoryPath), '$executionId.json');
  }

  static String cancelDirectoryPath(String appDirectoryPath) {
    return p.join(appDirectoryPath, cancelSubdirectoryName);
  }

  static String cancelFilePath(String appDirectoryPath, String executionId) {
    return p.join(cancelDirectoryPath(appDirectoryPath), '$executionId.json');
  }

  static String materializedDirectoryPath(String appDirectoryPath) {
    return p.join(appDirectoryPath, materializedSubdirectoryName);
  }

  static String materializedFilePath(String appDirectoryPath, String executionId) {
    return p.join(materializedDirectoryPath(appDirectoryPath), '$executionId.json');
  }
}
