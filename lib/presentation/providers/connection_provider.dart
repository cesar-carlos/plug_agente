import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/bootstrap/hub_connection_shutdown_registry.dart';
import 'package:plug_agente/application/coordinators/hub_connection/hub_connection_coordinator.dart';
import 'package:plug_agente/application/ports/hub_recovery_ui_sink.dart';
import 'package:plug_agente/application/ports/i_connection_context_source.dart';
import 'package:plug_agente/application/ports/i_hub_connection_shutdown_port.dart';
import 'package:plug_agente/application/ports/i_hub_recovery_auth_bridge.dart';
import 'package:plug_agente/application/services/connection_db_diagnostics_coordinator.dart';
import 'package:plug_agente/application/services/hub_access_token_refresh_gate.dart';
import 'package:plug_agente/application/services/hub_access_token_renewer.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/application/state/hub_connection_display_state.dart';
import 'package:plug_agente/application/use_cases/check_hub_availability.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/hub_resilience_config.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/value_objects/hub_recovery_diagnostics_snapshot.dart';
import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';
import 'package:plug_agente/presentation/adapters/hub_recovery_auth_bridge.dart';
import 'package:plug_agente/presentation/adapters/presentation_connection_context_source.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:result_dart/result_dart.dart';

export 'connection_display_state.dart' show ConnectionStatus;

class ConnectionProvider extends ChangeNotifier implements HubRecoveryUiSink {
  ConnectionProvider(
    ConnectToHub connectToHubUseCase,
    TestDbConnection testDbConnectionUseCase,
    CheckOdbcDriver checkOdbcDriverUseCase, {
    required ITransportClient transportClient,
    HubSessionCoordinator? hubSessionCoordinator,
    HubSessionCoordinator? hubRecoveryAuthCoordinator,
    IHubRecoveryAuthBridge? hubRecoveryAuthBridge,
    IConnectionContextSource? connectionContextSource,
    CheckHubAvailability? checkHubAvailabilityUseCase,
    AuthProvider? authProvider,
    ConfigProvider? configProvider,
    HubResilienceConfig? hubResilience,
    FeatureFlags? featureFlags,
    Duration initialReconnectDelay = HubConnectionCoordinator.defaultInitialReconnectDelay,
    Duration maxReconnectDelay = HubConnectionCoordinator.defaultMaxReconnectDelay,
    int tokenRefreshIntervalAttempts = HubConnectionCoordinator.defaultTokenRefreshIntervalAttempts,
    int maxReconnectAttempts = HubConnectionCoordinator.defaultMaxReconnectAttempts,
    int hardReloginFailureThreshold = HubConnectionCoordinator.defaultHardReloginFailureThreshold,
    bool enableHardReloginRecovery = HubConnectionCoordinator.defaultEnableHardReloginRecovery,
    Duration? hubPersistentRetryInterval,
    int? hubPersistentRetryMaxFailedTicks,
    Duration? hubTokenRefreshMinInterval,
    Duration? hubHardReloginCooldown,
    Duration? capabilitiesNegotiationWatchdogOverride,
    Random? random,
    HubAccessTokenRefreshGate? hubAccessTokenRefreshGate,
    HubAccessTokenRenewer? hubAccessTokenRenewer,
    HubConnectionShutdownRegistry? hubConnectionShutdownRegistry,
    ConnectionDbDiagnosticsCoordinator? dbDiagnosticsCoordinator,
    HubConnectionCoordinator? hubConnectionCoordinator,
  }) : _hubConnectionShutdownRegistry = hubConnectionShutdownRegistry,
       _hubSessionCoordinator = hubSessionCoordinator ?? hubRecoveryAuthCoordinator,
       _authProvider = authProvider,
       _configProvider = configProvider,
       _dbDiagnosticsCoordinator =
           dbDiagnosticsCoordinator ??
           ConnectionDbDiagnosticsCoordinator(
             testDbConnectionUseCase: testDbConnectionUseCase,
             checkOdbcDriverUseCase: checkOdbcDriverUseCase,
           ) {
    _displayState = HubConnectionDisplayState();
    _connectionTrackingState = HubConnectionTrackingState();
    _contextSource =
        connectionContextSource ??
        PresentationConnectionContextSource(
          trackingState: _connectionTrackingState,
          authProvider: () => _authProvider,
          configProvider: () => _configProvider,
        );
    final recoveryAuthBridge =
        hubRecoveryAuthBridge ?? _buildRecoveryAuthBridge(_hubSessionCoordinator, _authProvider);

    _hubConnectionCoordinator =
        hubConnectionCoordinator ??
        HubConnectionCoordinator(
          connectToHubUseCase: connectToHubUseCase,
          transportClient: transportClient,
          displayState: _displayState,
          connectionTrackingState: _connectionTrackingState,
          uiSink: this,
          contextSource: _contextSource,
          isDisconnectRequested: () => _isDisconnectRequested,
          setDisconnectRequested: (requested) => _isDisconnectRequested = requested,
          reconnectQuietFailureLogCount: () => _reconnectQuietFailureLogCount,
          setReconnectQuietFailureLogCount: (count) => _reconnectQuietFailureLogCount = count,
          resetReconnectQuietFailureLogCount: () => _reconnectQuietFailureLogCount = 0,
          bumpReconnectQuietFailureLogCount: () => ++_reconnectQuietFailureLogCount,
          notifyStateChanged: notifyListeners,
          onNegotiatingWatchdogTimeoutWithoutContext: _onNegotiatingWatchdogTimeoutWithoutContext,
          onNegotiatingWatchdogTimeoutWithContext: _onNegotiatingWatchdogTimeoutWithContext,
          resolveProactiveRefreshAccessToken: _resolveProactiveRefreshAccessToken,
          resolveAuthProviderError: () => _authProvider?.error,
          normalizeToken: _normalizeToken,
          checkHubAvailabilityUseCase: checkHubAvailabilityUseCase,
          hubRecoveryAuthBridge: recoveryAuthBridge,
          hubAccessTokenRefreshGate: hubAccessTokenRefreshGate,
          hubAccessTokenRenewer: hubAccessTokenRenewer,
          hubResilience: hubResilience,
          featureFlags: featureFlags,
          initialReconnectDelay: initialReconnectDelay,
          maxReconnectDelay: maxReconnectDelay,
          tokenRefreshIntervalAttempts: tokenRefreshIntervalAttempts,
          maxReconnectAttempts: maxReconnectAttempts,
          hardReloginFailureThreshold: hardReloginFailureThreshold,
          enableHardReloginRecovery: enableHardReloginRecovery,
          hubPersistentRetryInterval: hubPersistentRetryInterval,
          hubPersistentRetryMaxFailedTicks: hubPersistentRetryMaxFailedTicks,
          hubTokenRefreshMinInterval: hubTokenRefreshMinInterval,
          hubHardReloginCooldown: hubHardReloginCooldown,
          capabilitiesNegotiationWatchdogOverride: capabilitiesNegotiationWatchdogOverride,
          random: random,
        );

    _hubConnectionShutdownPort = _HubConnectionShutdownPortAdapter(this);
    _hubConnectionShutdownRegistry?.bind(_hubConnectionShutdownPort);
  }

  final HubSessionCoordinator? _hubSessionCoordinator;
  AuthProvider? _authProvider;
  ConfigProvider? _configProvider;
  late final HubConnectionTrackingState _connectionTrackingState;
  late final IConnectionContextSource _contextSource;
  final HubConnectionShutdownRegistry? _hubConnectionShutdownRegistry;
  late final IHubConnectionShutdownPort _hubConnectionShutdownPort;
  final ConnectionDbDiagnosticsCoordinator _dbDiagnosticsCoordinator;
  late final HubConnectionCoordinator _hubConnectionCoordinator;
  bool _shutdownResourcesReleased = false;

  IHubRecoveryAuthBridge? _buildRecoveryAuthBridge(
    HubSessionCoordinator? sessionCoordinator,
    AuthProvider? authProvider,
  ) {
    if (sessionCoordinator == null || authProvider == null) {
      return null;
    }
    return HubRecoveryAuthBridge(
      sessionCoordinator: sessionCoordinator,
      authProvider: authProvider,
    );
  }

  IHubRecoveryAuthBridge? _hubRecoveryAuthBridge;

  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
    if (_hubRecoveryAuthBridge == null && _hubSessionCoordinator != null) {
      _hubRecoveryAuthBridge = _buildRecoveryAuthBridge(_hubSessionCoordinator, authProvider);
      if (_hubRecoveryAuthBridge != null) {
        setHubRecoveryAuthBridge(_hubRecoveryAuthBridge!);
      }
    }
  }

  void setConfigProvider(ConfigProvider configProvider) {
    _configProvider = configProvider;
  }

  void setHubRecoveryAuthBridge(IHubRecoveryAuthBridge bridge) {
    _hubRecoveryAuthBridge = bridge;
    _hubConnectionCoordinator.attachRecoveryAuthBridge(bridge);
  }

  late final HubConnectionDisplayState _displayState;
  bool _isDisconnectRequested = false;
  int _reconnectQuietFailureLogCount = 0;

  ConnectionStatus get status => _displayState.status;
  String get error => _displayState.error;
  bool get isDbConnected => _displayState.isDbConnected;
  String? get activeConfigId => _connectionTrackingState.lastConfigId;

  HubRecoveryUiHint get hubRecoveryUiHint => _displayState.hubRecoveryUiHint;

  @override
  void setHubRecoveryUiHint(HubRecoveryUiHint hint) {
    if (_displayState.hubRecoveryUiHint == hint) {
      return;
    }
    _displayState.hubRecoveryUiHint = hint;
    notifyListeners();
  }

  @override
  void clearHubRecoveryUiHint() {
    setHubRecoveryUiHint(HubRecoveryUiHint.none);
  }

  void setDbConnectionIndicator(bool connected) {
    if (_displayState.isDbConnected == connected) {
      return;
    }
    _displayState.isDbConnected = connected;
    notifyListeners();
  }

  bool get isConnected => _displayState.status == ConnectionStatus.connected;

  bool get isReconnecting => _displayState.isReconnecting || _displayState.status == ConnectionStatus.reconnecting;
  bool get isConnectingOrNegotiating =>
      _displayState.status == ConnectionStatus.connecting || _displayState.status == ConnectionStatus.negotiating;
  bool get isCheckingDriver => _displayState.isCheckingDriver;

  void _onNegotiatingWatchdogTimeoutWithoutContext({required int timeoutMs}) {
    _hubConnectionCoordinator.cancelNegotiatingWatchdog();
    final failure = domain_errors.ConnectionFailure.withContext(
      message: 'Protocol negotiation timed out. Reconnect to the hub or verify the server is responding.',
      context: {
        'operation': 'negotiating_watchdog',
        'timeout_ms': timeoutMs,
      },
    );
    _displayState.status = ConnectionStatus.error;
    _displayState.error = failure.toDisplayMessage();
    notifyListeners();
  }

  void _onNegotiatingWatchdogTimeoutWithContext() {
    setHubRecoveryUiHint(HubRecoveryUiHint.negotiationTimedOut);
    _displayState.status = ConnectionStatus.reconnecting;
    _displayState.error = '';
    notifyListeners();
  }

  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? configId,
    String? authToken,
    bool recoverOnFailure = false,
  }) => _hubConnectionCoordinator.connect(
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
  }) => _hubConnectionCoordinator.startPersistentHubRecovery(
    configId: configId,
    serverUrl: serverUrl,
    agentId: agentId,
    authToken: authToken,
  );

  Future<void> disconnectForShutdown() async {
    await disconnect();
    _releaseShutdownResources();
  }

  Future<void> disconnect() => _hubConnectionCoordinator.disconnect();

  Future<Result<bool>> testDbConnection(
    String connectionString, {
    bool recordGlobalError = true,
  }) => _dbDiagnosticsCoordinator.testDbConnection(
    connectionString,
    recordGlobalError: recordGlobalError,
    setDbConnectionIndicator: setDbConnectionIndicator,
    setGlobalError: (message) => _displayState.error = message,
    notifyStateChanged: notifyListeners,
  );

  void clearError() {
    _displayState.error = '';
    notifyListeners();
  }

  Future<Result<bool>> checkOdbcDriver(String driverName) => _dbDiagnosticsCoordinator.checkOdbcDriver(
    driverName,
    setCheckingDriver: (checking) => _displayState.isCheckingDriver = checking,
    setGlobalError: (message) => _displayState.error = message,
    notifyStateChanged: notifyListeners,
  );

  void _releaseShutdownResources() {
    if (_shutdownResourcesReleased) {
      return;
    }
    _shutdownResourcesReleased = true;
    _hubConnectionCoordinator.dispose();
    clearHubRecoveryUiHint();
  }

  @override
  void dispose() {
    _hubConnectionShutdownRegistry?.unbind(_hubConnectionShutdownPort);
    _releaseShutdownResources();
    super.dispose();
  }

  String? _resolveProactiveRefreshAccessToken() {
    final configId = _connectionTrackingState.lastConfigId;
    final authToken = _authProvider?.currentTokenForConfig(configId)?.token.trim();
    if (authToken != null && authToken.isNotEmpty) {
      return authToken;
    }
    final trackedToken = _connectionTrackingState.lastAuthToken?.trim();
    if (trackedToken != null && trackedToken.isNotEmpty) {
      return trackedToken;
    }
    return _contextSource.resolveAuthTokenForReconnect()?.trim();
  }

  String? _normalizeToken(String? token) {
    final normalized = token?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  HubRecoveryDiagnosticsSnapshot get hubRecoveryDiagnostics => _hubConnectionCoordinator.buildDiagnosticsSnapshot();
}

final class _HubConnectionShutdownPortAdapter implements IHubConnectionShutdownPort {
  const _HubConnectionShutdownPortAdapter(this._connectionProvider);

  final ConnectionProvider _connectionProvider;

  @override
  Future<void> disconnectForShutdown() => _connectionProvider.disconnectForShutdown();
}
