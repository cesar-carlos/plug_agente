import 'dart:math';

import 'package:plug_agente/application/coordinators/hub_connection/hub_connection_coordinator_assembly.dart';
import 'package:plug_agente/application/ports/hub_recovery_ui_sink.dart';
import 'package:plug_agente/application/ports/i_connection_context_source.dart';
import 'package:plug_agente/application/ports/i_hub_recovery_auth_bridge.dart';
import 'package:plug_agente/application/services/hub_access_token_refresh_gate.dart';
import 'package:plug_agente/application/services/hub_access_token_renewer.dart';
import 'package:plug_agente/application/services/hub_connection_session_orchestrator.dart';
import 'package:plug_agente/application/services/hub_persistent_retry_coordinator.dart';
import 'package:plug_agente/application/services/hub_proactive_token_refresh_scheduler.dart';
import 'package:plug_agente/application/services/hub_recovery_orchestrator.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/application/state/hub_connection_display_state.dart';
import 'package:plug_agente/application/state/hub_connection_tracking_state.dart';
import 'package:plug_agente/application/use_cases/check_hub_availability.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/hub_resilience_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/value_objects/hub_recovery_diagnostics_snapshot.dart';
import 'package:result_dart/result_dart.dart';

/// Owns hub session, recovery, token refresh, and transport orchestration.
final class HubConnectionCoordinator {
  HubConnectionCoordinator({
    required ConnectToHub connectToHubUseCase,
    required ITransportClient transportClient,
    required HubConnectionDisplayState displayState,
    required HubConnectionTrackingState connectionTrackingState,
    required HubRecoveryUiSink uiSink,
    required IConnectionContextSource contextSource,
    required bool Function() isDisconnectRequested,
    required void Function(bool requested) setDisconnectRequested,
    required int Function() reconnectQuietFailureLogCount,
    required void Function(int count) setReconnectQuietFailureLogCount,
    required void Function() resetReconnectQuietFailureLogCount,
    required int Function() bumpReconnectQuietFailureLogCount,
    required void Function() notifyStateChanged,
    required void Function({required int timeoutMs}) onNegotiatingWatchdogTimeoutWithoutContext,
    required void Function() onNegotiatingWatchdogTimeoutWithContext,
    required String? Function() resolveProactiveRefreshAccessToken,
    required String? Function() resolveAuthProviderError,
    required String? Function(String? token) normalizeToken,
    CheckHubAvailability? checkHubAvailabilityUseCase,
    IHubRecoveryAuthBridge? hubRecoveryAuthBridge,
    HubAccessTokenRefreshGate? hubAccessTokenRefreshGate,
    HubAccessTokenRenewer? hubAccessTokenRenewer,
    HubResilienceConfig? hubResilience,
    FeatureFlags? featureFlags,
    Duration initialReconnectDelay = defaultInitialReconnectDelay,
    Duration maxReconnectDelay = defaultMaxReconnectDelay,
    int tokenRefreshIntervalAttempts = defaultTokenRefreshIntervalAttempts,
    int maxReconnectAttempts = defaultMaxReconnectAttempts,
    int hardReloginFailureThreshold = defaultHardReloginFailureThreshold,
    bool enableHardReloginRecovery = defaultEnableHardReloginRecovery,
    Duration? hubPersistentRetryInterval,
    int? hubPersistentRetryMaxFailedTicks,
    int? hubPersistentUnreachableMaxFailedTicks,
    Duration? hubTokenRefreshMinInterval,
    Duration? hubHardReloginCooldown,
    Duration? capabilitiesNegotiationWatchdogOverride,
    Random? random,
  }) : _displayState = displayState,
       _isDisconnectRequested = isDisconnectRequested,
       _hubAccessTokenRenewer = hubAccessTokenRenewer,
       _tokenRefreshIntervalAttempts = tokenRefreshIntervalAttempts,
       _maxReconnectAttempts = maxReconnectAttempts,
       _hardReloginFailureThresholdOverride = hardReloginFailureThreshold,
       _enableHardReloginRecoveryOverride = enableHardReloginRecovery,
       _hubPersistentRetryIntervalOverride = hubPersistentRetryInterval,
       _hubPersistentRetryMaxFailedTicksOverride = hubPersistentRetryMaxFailedTicks,
       _hubPersistentUnreachableMaxFailedTicksOverride = hubPersistentUnreachableMaxFailedTicks,
       _hubHardReloginCooldownOverride = hubHardReloginCooldown,
       _hubResilience = hubResilience,
       _featureFlags = featureFlags {
    final gate =
        hubAccessTokenRefreshGate ??
        HubAccessTokenRefreshGate(
          minInterval: hubTokenRefreshMinInterval ?? ConnectionConstants.hubTokenRefreshMinInterval,
        );

    final bundle = assembleHubConnectionCoordinators(
      HubConnectionCoordinatorAssemblyInput(
        connectToHubUseCase: connectToHubUseCase,
        transportClient: transportClient,
        checkHubAvailabilityUseCase: checkHubAvailabilityUseCase,
        contextSource: contextSource,
        hubRecoveryAuthBridge: hubRecoveryAuthBridge,
        hubAccessTokenRefreshGate: gate,
        hubAccessTokenRenewer: hubAccessTokenRenewer,
        displayState: displayState,
        connectionTrackingState: connectionTrackingState,
        uiSink: uiSink,
        isDisconnectRequested: isDisconnectRequested,
        setDisconnectRequested: setDisconnectRequested,
        reconnectQuietFailureLogCount: reconnectQuietFailureLogCount,
        setReconnectQuietFailureLogCount: setReconnectQuietFailureLogCount,
        resetReconnectQuietFailureLogCount: resetReconnectQuietFailureLogCount,
        bumpReconnectQuietFailureLogCount: bumpReconnectQuietFailureLogCount,
        notifyStateChanged: notifyStateChanged,
        onNegotiatingWatchdogTimeoutWithoutContext: onNegotiatingWatchdogTimeoutWithoutContext,
        onNegotiatingWatchdogTimeoutWithContext: onNegotiatingWatchdogTimeoutWithContext,
        resolveProactiveRefreshAccessToken: resolveProactiveRefreshAccessToken,
        resolveAuthProviderError: resolveAuthProviderError,
        normalizeToken: normalizeToken,
        initialReconnectDelay: initialReconnectDelay,
        maxReconnectDelay: maxReconnectDelay,
        tokenRefreshIntervalAttempts: _tokenRefreshIntervalAttempts,
        maxReconnectAttempts: _maxReconnectAttempts,
        effectiveHardReloginRecoveryEnabled: _effectiveHardReloginRecoveryEnabled,
        effectiveHardReloginFailureThreshold: _effectiveHardReloginFailureThreshold,
        effectiveHubPersistentRetryMaxFailedTicks: () => _effectiveHubPersistentRetryMaxFailedTicks,
        effectiveHubPersistentUnreachableMaxFailedTicks: () =>
            _effectiveHubPersistentUnreachableMaxFailedTicks,
        effectiveHubPersistentRetryInterval: () => _effectiveHubPersistentRetryInterval,
        effectiveHubHardReloginCooldown: _effectiveHubHardReloginCooldown,
        hasAuthBridge: hubRecoveryAuthBridge != null,
        random: random,
        capabilitiesNegotiationWatchdogOverride: capabilitiesNegotiationWatchdogOverride,
      ),
    );

    _resilienceCoordinator = bundle.resilienceCoordinator;
    _hubRecoveryOrchestrator = bundle.hubRecoveryOrchestrator;
    _persistentRetryCoordinator = bundle.persistentRetryCoordinator;
    _proactiveTokenRefreshScheduler = bundle.proactiveTokenRefreshScheduler;
    _connectionSessionOrchestrator = bundle.connectionSessionOrchestrator;

    _validateConstructorArguments(
      tokenRefreshIntervalAttempts: tokenRefreshIntervalAttempts,
      maxReconnectAttempts: maxReconnectAttempts,
      hardReloginFailureThreshold: hardReloginFailureThreshold,
      hubTokenRefreshMinInterval: hubTokenRefreshMinInterval,
      hubHardReloginCooldown: hubHardReloginCooldown,
      capabilitiesNegotiationWatchdogOverride: capabilitiesNegotiationWatchdogOverride,
    );
  }

  static const Duration defaultInitialReconnectDelay = Duration(
    seconds: AppConstants.reconnectIntervalSeconds,
  );
  static const Duration defaultMaxReconnectDelay = Duration(seconds: 60);
  static const int defaultTokenRefreshIntervalAttempts = 2;
  static const int defaultMaxReconnectAttempts = ConnectionConstants.defaultHubRecoveryBurstMaxAttempts;
  static const int defaultHardReloginFailureThreshold = 3;
  static const bool defaultEnableHardReloginRecovery = true;

  final HubConnectionDisplayState _displayState;
  final bool Function() _isDisconnectRequested;
  final HubAccessTokenRenewer? _hubAccessTokenRenewer;
  final HubResilienceConfig? _hubResilience;
  final FeatureFlags? _featureFlags;

  late final HubResilienceCoordinator _resilienceCoordinator;
  late final HubRecoveryOrchestrator _hubRecoveryOrchestrator;
  late final HubPersistentRetryCoordinator _persistentRetryCoordinator;
  late final HubProactiveTokenRefreshScheduler _proactiveTokenRefreshScheduler;
  late final HubConnectionSessionOrchestrator _connectionSessionOrchestrator;

  bool _resourcesReleased = false;

  static const int _hardReloginMinThreshold = 1;
  static const int _hardReloginMaxThreshold = 20;

  final int _tokenRefreshIntervalAttempts;
  final int _maxReconnectAttempts;
  final int _hardReloginFailureThresholdOverride;
  final bool _enableHardReloginRecoveryOverride;
  final Duration? _hubPersistentRetryIntervalOverride;
  final int? _hubPersistentRetryMaxFailedTicksOverride;
  final int? _hubPersistentUnreachableMaxFailedTicksOverride;
  final Duration? _hubHardReloginCooldownOverride;

  Duration get _effectiveHubPersistentRetryInterval =>
      _hubPersistentRetryIntervalOverride ??
      _hubResilience?.persistentRetryInterval ??
      ConnectionConstants.hubPersistentRetryInterval;

  int get _effectiveHubPersistentRetryMaxFailedTicks =>
      _hubPersistentRetryMaxFailedTicksOverride ??
      _hubResilience?.maxFailedTicks ??
      ConnectionConstants.hubPersistentRetryMaxFailedTicks;

  int get _effectiveHubPersistentUnreachableMaxFailedTicks =>
      _hubPersistentUnreachableMaxFailedTicksOverride ??
      _hubResilience?.maxUnreachableFailedTicks ??
      ConnectionConstants.hubPersistentUnreachableMaxFailedTicks;

  Duration get _effectiveHubHardReloginCooldown =>
      _hubHardReloginCooldownOverride ?? ConnectionConstants.hubHardReloginCooldown;

  bool get _effectiveHardReloginRecoveryEnabled =>
      _featureFlags?.enableHubHardReloginRecovery ?? _enableHardReloginRecoveryOverride;

  int get _effectiveHardReloginFailureThreshold {
    final configured = _featureFlags?.hubHardReloginFailureThreshold ?? _hardReloginFailureThresholdOverride;
    return configured.clamp(_hardReloginMinThreshold, _hardReloginMaxThreshold);
  }

  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? configId,
    String? authToken,
    bool recoverOnFailure = false,
  }) => _connectionSessionOrchestrator.connect(
    serverUrl,
    agentId,
    configId: configId,
    authToken: authToken,
    recoverOnFailure: recoverOnFailure,
  );

  void startPersistentHubRecovery({
    required String configId,
    required String serverUrl,
    required String agentId,
    String? authToken,
  }) => _connectionSessionOrchestrator.startPersistentHubRecovery(
    configId: configId,
    serverUrl: serverUrl,
    agentId: agentId,
    authToken: authToken,
  );

  Future<void> disconnect() => _connectionSessionOrchestrator.disconnect();

  void cancelNegotiatingWatchdog() => _resilienceCoordinator.cancelNegotiatingWatchdog();

  void attachRecoveryAuthBridge(IHubRecoveryAuthBridge bridge) {
    _resilienceCoordinator.attachRecoveryAuthBridge(bridge);
    final renewer = _hubAccessTokenRenewer;
    if (renewer != null) {
      renewer.bindAuthBridge(bridge);
      renewer.setOnAccessTokenRestored(_onHubAccessTokenRestored);
    }
  }

  void _onHubAccessTokenRestored() {
    if (!_isDisconnectRequested() && _displayState.isConnected) {
      _proactiveTokenRefreshScheduler.reschedule();
    }
  }

  HubRecoveryDiagnosticsSnapshot buildDiagnosticsSnapshot() {
    return HubRecoveryDiagnosticsSnapshot(
      recoveryId: _resilienceCoordinator.recoveryId,
      connectionStatusName: _displayState.status.name,
      hubRecoveryUiHintName: _displayState.hubRecoveryUiHint.name,
      consecutiveReconnectFailures: _hubRecoveryOrchestrator.consecutiveReconnectFailures,
      persistentRetryTickCount: _hubRecoveryOrchestrator.persistentRetryTickCount,
      persistentFailureCount: _hubRecoveryOrchestrator.persistentFailureCount,
      persistentUnreachableFailureCount: _hubRecoveryOrchestrator.persistentUnreachableFailureCount,
      hardReloginAttemptedInCycle: _hubRecoveryOrchestrator.hardReloginAttemptedInCycle,
      lastError: _displayState.error,
    );
  }

  void dispose() {
    if (_resourcesReleased) {
      return;
    }
    _resourcesReleased = true;
    _proactiveTokenRefreshScheduler.dispose();
    _hubAccessTokenRenewer?.clearAuthBridge();
    _resilienceCoordinator.dispose();
    _persistentRetryCoordinator.dispose();
  }

  void _validateConstructorArguments({
    required int tokenRefreshIntervalAttempts,
    required int maxReconnectAttempts,
    required int hardReloginFailureThreshold,
    Duration? hubTokenRefreshMinInterval,
    Duration? hubHardReloginCooldown,
    Duration? capabilitiesNegotiationWatchdogOverride,
  }) {
    if (_tokenRefreshIntervalAttempts < 1) {
      throw ArgumentError.value(
        tokenRefreshIntervalAttempts,
        'tokenRefreshIntervalAttempts',
        'must be >= 1',
      );
    }
    if (_maxReconnectAttempts < 1) {
      throw ArgumentError.value(
        maxReconnectAttempts,
        'maxReconnectAttempts',
        'must be >= 1',
      );
    }
    if (_hardReloginFailureThresholdOverride < 1) {
      throw ArgumentError.value(
        hardReloginFailureThreshold,
        'hardReloginFailureThreshold',
        'must be >= 1',
      );
    }
    if (hubTokenRefreshMinInterval != null && hubTokenRefreshMinInterval.inMicroseconds < 0) {
      throw ArgumentError.value(
        hubTokenRefreshMinInterval,
        'hubTokenRefreshMinInterval',
        'must not be negative',
      );
    }
    if (hubHardReloginCooldown != null && hubHardReloginCooldown.inMicroseconds < 0) {
      throw ArgumentError.value(
        hubHardReloginCooldown,
        'hubHardReloginCooldown',
        'must not be negative',
      );
    }
    if (capabilitiesNegotiationWatchdogOverride != null &&
        capabilitiesNegotiationWatchdogOverride.inMicroseconds <= 0) {
      throw ArgumentError.value(
        capabilitiesNegotiationWatchdogOverride,
        'capabilitiesNegotiationWatchdogOverride',
        'must be positive',
      );
    }
  }
}
