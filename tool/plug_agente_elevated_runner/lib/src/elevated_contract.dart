import 'package:path/path.dart' as p;

/// Contract constants aligned with `AgentActionElevatedConstants` in the main app.
abstract final class ElevatedContract {
  static const int requestSchemaVersion = 1;
  static const int statusSchemaVersion = 1;

  static const String requestsSubdirectoryName = 'agent_actions/elevated/requests';
  static const String statusSubdirectoryName = 'agent_actions/elevated/status';
  static const String cancelSubdirectoryName = 'agent_actions/elevated/cancel';
  static const String materializedSubdirectoryName = 'agent_actions/elevated/materialized';

  static const int materializedSchemaVersion = 1;
  static const String databaseFileName = 'agent_config.db';

  static const Duration requestTtl = Duration(minutes: 5);
  static const Duration idleWaitBeforeExit = Duration(seconds: 2);
  static const Duration pollInterval = Duration(milliseconds: 250);

  static const int defaultMaxCapturedOutputBytes = 65536;

  static const Set<String> supportedElevatedActionTypeNames = <String>{
    'commandLine',
    'developer',
  };

  static String requestsDirectory(String appDirectoryPath) {
    return p.join(appDirectoryPath, requestsSubdirectoryName);
  }

  static String statusDirectory(String appDirectoryPath) {
    return p.join(appDirectoryPath, statusSubdirectoryName);
  }

  static String databasePath(String appDirectoryPath) {
    return p.join(appDirectoryPath, databaseFileName);
  }

  static String requestFilePath(String appDirectoryPath, String executionId) {
    return p.join(requestsDirectory(appDirectoryPath), '$executionId.json');
  }

  static String statusFilePath(String appDirectoryPath, String executionId) {
    return p.join(statusDirectory(appDirectoryPath), '$executionId.json');
  }

  static String cancelDirectory(String appDirectoryPath) {
    return p.join(appDirectoryPath, cancelSubdirectoryName);
  }

  static String cancelFilePath(String appDirectoryPath, String executionId) {
    return p.join(cancelDirectory(appDirectoryPath), '$executionId.json');
  }

  static String materializedDirectory(String appDirectoryPath) {
    return p.join(appDirectoryPath, materializedSubdirectoryName);
  }

  static String materializedFilePath(String appDirectoryPath, String executionId) {
    return p.join(materializedDirectory(appDirectoryPath), '$executionId.json');
  }
}
