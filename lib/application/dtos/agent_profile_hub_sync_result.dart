import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/domain/errors/failures.dart';

/// Result of attempting to push local profile catalog to the hub after a local save.
sealed class AgentProfileHubSyncResult {
  const AgentProfileHubSyncResult();
}

/// Hub sync was not attempted (offline, missing credentials, etc.).
final class AgentProfileHubSyncSkipped extends AgentProfileHubSyncResult {
  const AgentProfileHubSyncSkipped(this.reason);

  final AgentProfileHubSyncSkipReason reason;
}

enum AgentProfileHubSyncSkipReason {
  missingCredentials,
  hubNotConnected,
}

/// Remote PATCH succeeded and returned a new catalog version.
final class AgentProfileHubSyncSucceeded extends AgentProfileHubSyncResult {
  const AgentProfileHubSyncSucceeded({
    required this.profileVersion,
    this.profileUpdatedAt,
  });

  final int profileVersion;
  final String? profileUpdatedAt;
}

/// PATCH failed after local save.
final class AgentProfileHubSyncPushFailed extends AgentProfileHubSyncResult {
  const AgentProfileHubSyncPushFailed(this.failure);

  final Failure failure;
}

/// PATCH succeeded but persisting [profileVersion] locally failed.
final class AgentProfileHubSyncCatalogPersistFailed extends AgentProfileHubSyncResult {
  const AgentProfileHubSyncCatalogPersistFailed({
    required this.profileVersion,
    required this.persistErrorMessage,
    this.profileUpdatedAt,
  });

  final int profileVersion;
  final String? profileUpdatedAt;
  final String persistErrorMessage;
}

/// Catalog was loaded from the hub (reload flow).
final class AgentProfileHubReloaded extends AgentProfileHubSyncResult {
  const AgentProfileHubReloaded({
    required this.profile,
    required this.profileVersion,
    this.profileUpdatedAt,
  });

  final AgentProfile profile;
  final int profileVersion;
  final String? profileUpdatedAt;
}
