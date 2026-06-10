/// Staging metadata for restoring local app data from a backup ZIP.
///
/// The implementing service is responsible for deleting [tempDirectoryPath] when done.
class RestoreStagingSnapshot {
  const RestoreStagingSnapshot({
    required this.tempDirectoryPath,
    required this.stagedDatabasePath,
    required this.backupUserVersion,
    required this.duplicateRisk,
    this.stagedSettingsPath,
    this.stagedSecureStorageSecretsPath,
    this.manifestInstallationId,
    this.currentInstallationId,
    this.manifestSecureStorageSecretsIncluded = false,
    this.manifestSecureStorageSecretsEntryCount,
  });

  final String tempDirectoryPath;
  final String stagedDatabasePath;
  final String? stagedSettingsPath;
  final String? stagedSecureStorageSecretsPath;
  final int backupUserVersion;
  final DuplicateRiskLevel duplicateRisk;
  final String? manifestInstallationId;
  final String? currentInstallationId;
  final bool manifestSecureStorageSecretsIncluded;
  final int? manifestSecureStorageSecretsEntryCount;
}

enum DuplicateRiskLevel {
  /// No conflict detected or backup agent is not listed as connected.
  none,

  /// The hub reports this agent ID as currently connected (same backup restored elsewhere).
  agentListedAsConnectedOnHub,

  /// Could not reach the hub or refresh a token; user must acknowledge uncertainty.
  verificationImpossible,
}
