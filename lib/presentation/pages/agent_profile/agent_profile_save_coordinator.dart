import 'package:plug_agente/application/dtos/agent_profile_hub_sync_result.dart';
import 'package:plug_agente/application/services/agent_register_profile_provider.dart';
import 'package:plug_agente/application/use_cases/fetch_agent_hub_profile.dart';
import 'package:plug_agente/application/use_cases/sync_agent_profile_with_hub.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/application/validation/agent_profile_validation_messages.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/mappers/hub_auth_failure_l10n.dart';
import 'package:plug_agente/presentation/pages/agent_profile/agent_profile_save_outcome.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';

/// Orchestrates local persistence and optional hub catalog sync for agent profile.
///
/// Hub catalog is also sent on Socket.IO connect via `agent.register` snapshot;
/// REST PATCH here is for explicit save while authenticated and connected.
class AgentProfileSaveCoordinator {
  AgentProfileSaveCoordinator({
    required ConfigProvider configProvider,
    required AuthProvider authProvider,
    required ConnectionProvider connectionProvider,
    required SyncAgentProfileWithHub syncAgentProfileWithHub,
    required FetchAgentHubProfile fetchAgentHubProfile,
    required AgentRegisterProfileProvider registerProfileProvider,
  }) : _configProvider = configProvider,
       _authProvider = authProvider,
       _connectionProvider = connectionProvider,
       _syncAgentProfileWithHub = syncAgentProfileWithHub,
       _fetchAgentHubProfile = fetchAgentHubProfile,
       _registerProfileProvider = registerProfileProvider;

  final ConfigProvider _configProvider;
  final AuthProvider _authProvider;
  final ConnectionProvider _connectionProvider;
  final SyncAgentProfileWithHub _syncAgentProfileWithHub;
  final FetchAgentHubProfile _fetchAgentHubProfile;
  final AgentRegisterProfileProvider _registerProfileProvider;

  Future<AgentProfileSaveOutcome> save(
    AgentProfile profile, {
    AgentProfileValidationMessages? validationMessages,
    AppLocalizations? localizations,
  }) async {
    _configProvider.updateAgentProfile(profile);
    final saveResult = await _configProvider.saveConfig();

    if (saveResult.isError()) {
      return AgentProfileSaveLocalFailure(
        errorMessage: saveResult.exceptionOrNull()!.toDisplayMessage(),
      );
    }

    _registerProfileProvider.clearCache();
    return _syncAfterLocalSave(
      profile,
      validationMessages: validationMessages,
      localizations: localizations,
    );
  }

  /// Retries hub PATCH only (local profile already saved).
  Future<AgentProfileSaveOutcome> retryHubSync(
    AgentProfile profile, {
    AgentProfileValidationMessages? validationMessages,
    AppLocalizations? localizations,
  }) {
    return _syncAfterLocalSave(
      profile,
      validationMessages: validationMessages,
      localizations: localizations,
    );
  }

  /// Loads catalog from hub, updates local version, and returns profile for the form.
  Future<AgentProfileSaveOutcome> reloadProfileFromHub({
    required AgentProfile fallbackProfile,
    AgentProfileValidationMessages? validationMessages,
    AppLocalizations? localizations,
  }) async {
    final credentials = _readSyncCredentials();
    if (credentials == null) {
      return const AgentProfileSaveLocalOnly();
    }

    final fetchResult = await _fetchAgentHubProfile(
      serverUrl: credentials.serverUrl,
      agentId: credentials.agentId,
      accessToken: credentials.accessToken,
      configId: credentials.configId,
      validationMessages: validationMessages ?? AgentProfileValidationMessages.english,
    );

    if (fetchResult.isError()) {
      final failure = _asFailure(fetchResult.exceptionOrNull()!);
      _surfaceHubAuthFailureIfNeeded(failure, localizations);
      return AgentProfileSaveHubPartialFailure(
        hubErrorMessage: _hubErrorMessage(failure, localizations),
        failure: failure,
        profile: fallbackProfile,
      );
    }

    final fetched = fetchResult.getOrThrow();
    _configProvider.updateAgentProfile(fetched.profile);
    final persistResult = await _configProvider.persistHubProfileCatalogSync(
      profileVersion: fetched.profileVersion,
      profileUpdatedAtIso: fetched.profileUpdatedAt,
    );

    if (persistResult.isError()) {
      return AgentProfileSaveHubCatalogPersistFailure(
        message: persistResult.exceptionOrNull()!.toDisplayMessage(),
        profile: fetched.profile,
      );
    }

    _registerProfileProvider.clearCache();
    return AgentProfileSaveReloadedFromHub(profile: fetched.profile);
  }

  Future<AgentProfileSaveOutcome> _syncAfterLocalSave(
    AgentProfile profile, {
    AgentProfileValidationMessages? validationMessages,
    AppLocalizations? localizations,
  }) async {
    final credentials = _readSyncCredentials();
    if (credentials == null) {
      return const AgentProfileSaveLocalOnly();
    }

    final syncResult = await _syncAgentProfileWithHub(
      profile: profile,
      serverUrl: credentials.serverUrl,
      agentId: credentials.agentId,
      accessToken: credentials.accessToken,
      isHubConnected: _connectionProvider.isConnected,
      expectedProfileVersion: credentials.hubProfileVersion,
      configId: credentials.configId,
    );

    return _mapSyncResult(syncResult, profile, localizations: localizations);
  }

  Future<AgentProfileSaveOutcome> _mapSyncResult(
    AgentProfileHubSyncResult syncResult,
    AgentProfile profile, {
    AppLocalizations? localizations,
  }) async {
    switch (syncResult) {
      case AgentProfileHubSyncSkipped():
        return const AgentProfileSaveLocalOnly();
      case AgentProfileHubSyncPushFailed(failure: final failure):
        _surfaceHubAuthFailureIfNeeded(failure, localizations);
        return AgentProfileSaveHubPartialFailure(
          hubErrorMessage: _hubErrorMessage(failure, localizations),
          failure: failure,
          profile: profile,
        );
      case AgentProfileHubSyncSucceeded(
        profileVersion: final version,
        profileUpdatedAt: final updatedAt,
      ):
        final persistResult = await _configProvider.persistHubProfileCatalogSync(
          profileVersion: version,
          profileUpdatedAtIso: updatedAt,
        );
        if (persistResult.isError()) {
          return AgentProfileSaveHubCatalogPersistFailure(
            message: persistResult.exceptionOrNull()!.toDisplayMessage(),
            profile: profile,
          );
        }
        _registerProfileProvider.clearCache();
        return const AgentProfileSaveSynced();
      case AgentProfileHubReloaded(profile: final reloaded):
        return AgentProfileSaveReloadedFromHub(profile: reloaded);
      case AgentProfileHubSyncCatalogPersistFailed():
        return AgentProfileSaveHubCatalogPersistFailure(
          message: syncResult.persistErrorMessage,
          profile: profile,
        );
    }
  }

  _SyncCredentials? _readSyncCredentials() {
    final savedConfig = _configProvider.currentConfig;
    if (savedConfig == null) {
      return null;
    }

    final accessToken = _resolveAccessToken(savedConfig.id, savedConfig.authToken);
    if (accessToken.isEmpty || savedConfig.serverUrl.trim().isEmpty || savedConfig.agentId.trim().isEmpty) {
      return null;
    }

    return _SyncCredentials(
      configId: savedConfig.id,
      serverUrl: savedConfig.serverUrl,
      agentId: savedConfig.agentId,
      accessToken: accessToken,
      hubProfileVersion: savedConfig.hubProfileVersion,
    );
  }

  void _surfaceHubAuthFailureIfNeeded(Failure failure, AppLocalizations? localizations) {
    if (!isHubSessionAuthFailure(failure)) {
      return;
    }
    final message = localizations == null ? failure.message : hubAuthFailureDisplayMessage(failure, localizations);
    _authProvider.setRecoveryError(message);
  }

  String _hubErrorMessage(Failure failure, AppLocalizations? localizations) {
    if (localizations == null) {
      return failure.message;
    }
    return hubAuthFailureDisplayMessage(failure, localizations);
  }

  String _resolveAccessToken(String? configId, String? configStoredToken) {
    final headerToken = _authProvider.currentTokenForConfig(configId)?.token.trim();
    if (headerToken != null && headerToken.isNotEmpty) {
      return headerToken;
    }
    return configStoredToken?.trim() ?? '';
  }

  Failure _asFailure(Object error) {
    if (error is Failure) {
      return error;
    }
    return ServerFailure(error.toString());
  }
}

class _SyncCredentials {
  const _SyncCredentials({
    required this.serverUrl,
    required this.agentId,
    required this.accessToken,
    this.configId,
    this.hubProfileVersion,
  });

  final String? configId;
  final String serverUrl;
  final String agentId;
  final String accessToken;
  final int? hubProfileVersion;
}
