import 'package:plug_agente/application/services/agent_register_profile_provider.dart';
import 'package:plug_agente/application/use_cases/push_agent_profile_to_hub.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/presentation/pages/agent_profile/agent_profile_save_outcome.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';

/// Orchestrates the persistence + Hub synchronization steps required to save
/// the agent profile.
///
/// Lives in the presentation layer because it composes presentation providers
/// (config, auth) with the existing application use case responsible for the
/// remote PATCH. Keeping it here avoids leaking provider state into the
/// application layer while letting the page widget remain a thin renderer.
class AgentProfileSaveCoordinator {
  AgentProfileSaveCoordinator({
    required ConfigProvider configProvider,
    required AuthProvider authProvider,
    required PushAgentProfileToHub pushAgentProfileToHub,
    required AgentRegisterProfileProvider registerProfileProvider,
  }) : _configProvider = configProvider,
       _authProvider = authProvider,
       _pushAgentProfileToHub = pushAgentProfileToHub,
       _registerProfileProvider = registerProfileProvider;

  final ConfigProvider _configProvider;
  final AuthProvider _authProvider;
  final PushAgentProfileToHub _pushAgentProfileToHub;
  final AgentRegisterProfileProvider _registerProfileProvider;

  Future<AgentProfileSaveOutcome> save(AgentProfile profile) async {
    _configProvider.updateAgentProfile(profile);
    final saveResult = await _configProvider.saveConfig();

    if (saveResult.isError()) {
      return AgentProfileSaveLocalFailure(
        errorMessage: saveResult.exceptionOrNull()!.toDisplayMessage(),
      );
    }

    _registerProfileProvider.clearCache();

    final savedConfig = _configProvider.currentConfig;
    final accessToken = _resolveAccessToken(savedConfig?.id, savedConfig?.authToken);

    final canSync =
        accessToken.isNotEmpty &&
        savedConfig != null &&
        savedConfig.serverUrl.trim().isNotEmpty &&
        savedConfig.agentId.trim().isNotEmpty;

    if (!canSync) {
      return const AgentProfileSaveLocalOnly();
    }

    final pushResult = await _pushAgentProfileToHub(
      serverUrl: savedConfig.serverUrl,
      agentId: savedConfig.agentId,
      accessToken: accessToken,
      profile: profile,
      expectedProfileVersion: savedConfig.hubProfileVersion,
    );

    if (pushResult.isError()) {
      return AgentProfileSaveHubPartialFailure(
        hubErrorMessage: pushResult.exceptionOrNull()!.toDisplayMessage(),
      );
    }

    final synced = pushResult.getOrThrow();
    final persistResult = await _configProvider.persistHubProfileCatalogSync(
      profileVersion: synced.profileVersion,
      profileUpdatedAtIso: synced.profileUpdatedAt,
    );

    persistResult.fold(
      (_) => _registerProfileProvider.clearCache(),
      (Object failure) {
        AppLogger.warning(
          'Hub profile synced but failed to persist catalog version locally: '
          '${failure.toDisplayMessage()}',
        );
      },
    );

    return const AgentProfileSaveSynced();
  }

  String _resolveAccessToken(String? configId, String? configStoredToken) {
    final headerToken = _authProvider.currentTokenForConfig(configId)?.token.trim();
    if (headerToken != null && headerToken.isNotEmpty) {
      return headerToken;
    }
    return configStoredToken?.trim() ?? '';
  }
}
