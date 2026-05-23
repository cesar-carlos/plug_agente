import 'package:plug_agente/application/ports/i_connection_context_source.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';

/// Mutable hub connection tracking state shared between presentation surfaces.
class HubConnectionTrackingState {
  String? lastConfigId;
  String? lastServerUrl;
  String? lastAgentId;
  String? lastAuthToken;
  bool sessionAuthInvalid = false;
}

/// Resolves hub connection context from tracked state and live providers.
class PresentationConnectionContextSource implements IConnectionContextSource {
  PresentationConnectionContextSource({
    required HubConnectionTrackingState trackingState,
    AuthProvider? Function()? authProvider,
    ConfigProvider? Function()? configProvider,
  }) : _trackingState = trackingState,
       _authProvider = authProvider ?? (() => null),
       _configProvider = configProvider ?? (() => null);

  final HubConnectionTrackingState _trackingState;
  final AuthProvider? Function() _authProvider;
  final ConfigProvider? Function() _configProvider;

  HubConnectionTrackingState get trackingState => _trackingState;

  @override
  HubConnectionContext? resolveConnectionContext() {
    final config = _resolveTrackedConfig();
    final configServerUrl = config?.serverUrl.trim();
    final configAgentId = config?.agentId.trim();
    final configId = _trackingState.lastConfigId ?? config?.id;
    final serverUrl =
        _trackingState.lastServerUrl ??
        ((configServerUrl != null && configServerUrl.isNotEmpty) ? configServerUrl : null);
    final agentId =
        _trackingState.lastAgentId ?? ((configAgentId != null && configAgentId.isNotEmpty) ? configAgentId : null);

    if (configId == null || serverUrl == null || agentId == null) {
      return null;
    }

    return HubConnectionContext(
      configId: configId,
      serverUrl: serverUrl,
      agentId: agentId,
    );
  }

  @override
  String? resolveAuthTokenForReconnect() {
    final liveToken = _normalizeToken(
      _authProvider()?.currentTokenForConfig(_trackingState.lastConfigId)?.token,
    );
    if (liveToken != null) {
      _trackingState.sessionAuthInvalid = false;
      return _trackingState.lastAuthToken = liveToken;
    }

    if (_trackingState.sessionAuthInvalid) {
      return null;
    }

    final configToken = _normalizeToken(_resolveTrackedConfig()?.authToken);
    if (configToken != null) {
      return _trackingState.lastAuthToken = configToken;
    }

    return _trackingState.lastAuthToken;
  }

  @override
  String resolveActiveConfigId(String? candidateConfigId) {
    final normalized = candidateConfigId?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }

    final currentConfigId = _configProvider()?.currentConfig?.id.trim();
    if (currentConfigId != null && currentConfigId.isNotEmpty) {
      return currentConfigId;
    }

    return _trackingState.lastConfigId ?? 'unknown-config';
  }

  Config? _resolveTrackedConfig() {
    final config = _configProvider()?.currentConfig;
    if (config == null) {
      return null;
    }

    final configId = _trackingState.lastConfigId?.trim();
    if (configId == null || configId.isEmpty || config.id == configId) {
      return config;
    }

    return null;
  }

  String? _normalizeToken(String? token) {
    final normalized = token?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
