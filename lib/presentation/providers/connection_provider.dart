import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/bootstrap/hub_connection_shutdown_registry.dart';
import 'package:plug_agente/application/ports/hub_recovery_ui_sink.dart';
import 'package:plug_agente/application/ports/i_connection_context_source.dart';
import 'package:plug_agente/application/ports/i_hub_connection_shutdown_port.dart';
import 'package:plug_agente/application/ports/i_hub_recovery_auth_bridge.dart';
import 'package:plug_agente/application/services/connection_db_diagnostics_coordinator.dart';
import 'package:plug_agente/application/services/hub_access_token_refresh_gate.dart';
import 'package:plug_agente/application/services/hub_access_token_renewer.dart';
import 'package:plug_agente/application/services/hub_connection_session_orchestrator.dart';
import 'package:plug_agente/application/services/hub_persistent_retry_coordinator.dart';
import 'package:plug_agente/application/services/hub_proactive_token_refresh_scheduler.dart';
import 'package:plug_agente/application/services/hub_recovery_orchestrator.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/application/use_cases/check_hub_availability.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/hub_resilience_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/value_objects/hub_recovery_diagnostics_snapshot.dart';
import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';
import 'package:plug_agente/presentation/adapters/hub_recovery_auth_bridge.dart';
import 'package:plug_agente/presentation/adapters/presentation_connection_context_source.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection/connection_provider_coordinator_assembly.dart';
import 'package:plug_agente/presentation/providers/connection_display_state.dart';
import 'package:result_dart/result_dart.dart';

export 'connection_display_state.dart' show ConnectionStatus;

class ConnectionProvider extends ChangeNotifier implements HubRecoveryUiSink {
  ConnectionProvider(
    this._connectToHubUseCase,
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
    Duration initialReconnectDelay = _defaultInitialReconnectDelay,
    Duration maxReconnectDelay = _defaultMaxReconnectDelay,
    int tokenRefreshIntervalAttempts = _defaultTokenRefreshIntervalAttempts,
    int maxReconnectAttempts = _defaultMaxReconnectAttempts,
    int hardReloginFailureThreshold = _defaultHardReloginFailureThreshold,
    bool enableHardReloginRecovery = _defaultEnableHardReloginRecovery,
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
  }) : _checkHubAvailabilityUseCase = checkHubAvailabilityUseCase,
       _hubConnectionShutdownRegistry = hubConnectionShutdownRegistry,
       _hubSessionCoordinator = hubSessionCoordinator ?? hubRecoveryAuthCoordinator,
       _authProvider = authProvider,
       _configProvider = configProvider,
       _transportClient = transportClient,
       _hubResilience = hubResilience,
       _featureFlags = featureFlags,
       _tokenRefreshIntervalAttempts = tokenRefreshIntervalAttempts,
       _maxReconnectAttempts = maxReconnectAttempts,
       _hardReloginFailureThresholdOverride = hardReloginFailureThreshold,
       _enableHardReloginRecoveryOverride = enableHardReloginRecovery,
       _hubPersistentRetryIntervalOverride = hubPersistentRetryInterval,
       _hubPersistentRetryMaxFailedTicksOverride = hubPersistentRetryMaxFailedTicks,
       _hubHardReloginCooldownOverride = hubHardReloginCooldown,
       _hubAccessTokenRenewer = hubAccessTokenRenewer,
       _dbDiagnosticsCoordinator =
           dbDiagnosticsCoordinator ??
           ConnectionDbDiagnosticsCoordinator(
             testDbConnectionUseCase: testDbConnectionUseCase,
             checkOdbcDriverUseCase: checkOdbcDriverUseCase,
           ) {
    _displayState = ConnectionDisplayState();
    _connectionTrackingState = HubConnectionTrackingState();
    _contextSource =
        connectionContextSource ??
        PresentationConnectionContextSource(
          trackingState: _connectionTrackingState,
          authProvider: () => _authProvider,
          configProvider: () => _configProvider,
        );
    _hubRecoveryAuthBridge = hubRecoveryAuthBridge ?? _buildRecoveryAuthBridge(_hubSessionCoordinator, _authProvider);
    _hubAccessTokenRefreshGate =
        hubAccessTokenRefreshGate ??
        HubAccessTokenRefreshGate(
          minInterval: hubTokenRefreshMinInterval ?? ConnectionConstants.hubTokenRefreshMinInterval,
        );

    final coordinators = assembleConnectionProviderCoordinators(
      ConnectionProviderCoordinatorAssemblyInput(
        connectToHubUseCase: _connectToHubUseCase,
        transportClient: _transportClient,
        checkHubAvailabilityUseCase: _checkHubAvailabilityUseCase,
        contextSource: _contextSource,
        hubRecoveryAuthBridge: _hubRecoveryAuthBridge,
        hubAccessTokenRefreshGate: _hubAccessTokenRefreshGate,
        hubAccessTokenRenewer: _hubAccessTokenRenewer,
        displayState: _displayState,
        connectionTrackingState: _connectionTrackingState,
        uiSink: this,
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
        initialReconnectDelay: initialReconnectDelay,
        maxReconnectDelay: maxReconnectDelay,
        tokenRefreshIntervalAttempts: _tokenRefreshIntervalAttempts,
        maxReconnectAttempts: _maxReconnectAttempts,
        effectiveHardReloginRecoveryEnabled: _effectiveHardReloginRecoveryEnabled,
        effectiveHardReloginFailureThreshold: _effectiveHardReloginFailureThreshold,
        effectiveHubPersistentRetryMaxFailedTicks: _effectiveHubPersistentRetryMaxFailedTicks,
        effectiveHubPersistentRetryInterval: _effectiveHubPersistentRetryInterval,
        effectiveHubHardReloginCooldown: _effectiveHubHardReloginCooldown,
        hasAuthBridge: _hubRecoveryAuthBridge != null,
        random: random,
        capabilitiesNegotiationWatchdogOverride: capabilitiesNegotiationWatchdogOverride,
      ),
    );

    _resilienceCoordinator = coordinators.resilienceCoordinator;
    _hubRecoveryOrchestrator = coordinators.hubRecoveryOrchestrator;
    _persistentRetryCoordinator = coordinators.persistentRetryCoordinator;
    _proactiveTokenRefreshScheduler = coordinators.proactiveTokenRefreshScheduler;
    _connectionSessionOrchestrator = coordinators.connectionSessionOrchestrator;

    _hubConnectionShutdownPort = _HubConnectionShutdownPortAdapter(this);
    _hubConnectionShutdownRegistry?.bind(_hubConnectionShutdownPort);
    _validateConstructorArguments(
      tokenRefreshIntervalAttempts: tokenRefreshIntervalAttempts,
      maxReconnectAttempts: maxReconnectAttempts,
      hardReloginFailureThreshold: hardReloginFailureThreshold,
      hubTokenRefreshMinInterval: hubTokenRefreshMinInterval,
      hubHardReloginCooldown: hubHardReloginCooldown,
      capabilitiesNegotiationWatchdogOverride: capabilitiesNegotiationWatchdogOverride,
    );
  }

  final CheckHubAvailability? _checkHubAvailabilityUseCase;
  final HubSessionCoordinator? _hubSessionCoordinator;
  final ConnectToHub _connectToHubUseCase;
  AuthProvider? _authProvider;
  ConfigProvider? _configProvider;
  IHubRecoveryAuthBridge? _hubRecoveryAuthBridge;
  late final HubConnectionTrackingState _connectionTrackingState;
  late final IConnectionContextSource _contextSource;
  final ITransportClient _transportClient;
  final HubResilienceConfig? _hubResilience;
  final FeatureFlags? _featureFlags;
  final HubConnectionShutdownRegistry? _hubConnectionShutdownRegistry;
  late final IHubConnectionShutdownPort _hubConnectionShutdownPort;
  final ConnectionDbDiagnosticsCoordinator _dbDiagnosticsCoordinator;
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

  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
    if (_hubRecoveryAuthBridge == null && _hubSessionCoordinator != null) {
      _hubRecoveryAuthBridge = _buildRecoveryAuthBridge(_hubSessionCoordinator, authProvider);
      _resilienceCoordinator.attachRecoveryAuthBridge(_hubRecoveryAuthBridge);
    }
  }

  void setConfigProvider(ConfigProvider configProvider) {
    _configProvider = configProvider;
  }

  void setHubRecoveryAuthBridge(IHubRecoveryAuthBridge bridge) {
    _hubRecoveryAuthBridge = bridge;
    _resilienceCoordinator.attachRecoveryAuthBridge(bridge);
    final renewer = _hubAccessTokenRenewer;
    if (renewer != null) {
      renewer.bindAuthBridge(bridge);
      renewer.setOnAccessTokenRestored(_onHubAccessTokenRestored);
    }
  }

  void _onHubAccessTokenRestored() {
    if (!_isDisconnectRequested && isConnected) {
      _proactiveTokenRefreshScheduler.reschedule();
    }
  }

  late final ConnectionDisplayState _displayState;
  bool _isDisconnectRequested = false;
  int _reconnectQuietFailureLogCount = 0;
  late final HubAccessTokenRefreshGate _hubAccessTokenRefreshGate;
  final HubAccessTokenRenewer? _hubAccessTokenRenewer;
  late final HubResilienceCoordinator _resilienceCoordinator;
  late final HubRecoveryOrchestrator _hubRecoveryOrchestrator;
  late final HubPersistentRetryCoordinator _persistentRetryCoordinator;
  late final HubProactiveTokenRefreshScheduler _proactiveTokenRefreshScheduler;
  late final HubConnectionSessionOrchestrator _connectionSessionOrchestrator;

  static const Duration _defaultInitialReconnectDelay = Duration(
    seconds: AppConstants.reconnectIntervalSeconds,
  );
  static const Duration _defaultMaxReconnectDelay = Duration(seconds: 60);

  static const int _defaultTokenRefreshIntervalAttempts = 2;
  static const int _defaultMaxReconnectAttempts = ConnectionConstants.defaultHubRecoveryBurstMaxAttempts;
  final int _tokenRefreshIntervalAttempts;
  final int _maxReconnectAttempts;
  final int _hardReloginFailureThresholdOverride;
  final bool _enableHardReloginRecoveryOverride;
  final Duration? _hubPersistentRetryIntervalOverride;
  final int? _hubPersistentRetryMaxFailedTicksOverride;
  final Duration? _hubHardReloginCooldownOverride;

  static const int _defaultHardReloginFailureThreshold = 3;
  static const bool _defaultEnableHardReloginRecovery = true;
  static const int _hardReloginMinThreshold = 1;
  static const int _hardReloginMaxThreshold = 20;

  Duration get _effectiveHubPersistentRetryInterval =>
      _hubPersistentRetryIntervalOverride ??
      _hubResilience?.persistentRetryInterval ??
      ConnectionConstants.hubPersistentRetryInterval;

  int get _effectiveHubPersistentRetryMaxFailedTicks =>
      _hubPersistentRetryMaxFailedTicksOverride ??
      _hubResilience?.maxFailedTicks ??
      ConnectionConstants.hubPersistentRetryMaxFailedTicks;

  Duration get _effectiveHubHardReloginCooldown =>
      _hubHardReloginCooldownOverride ?? ConnectionConstants.hubHardReloginCooldown;

  bool get _effectiveHardReloginRecoveryEnabled =>
      _featureFlags?.enableHubHardReloginRecovery ?? _enableHardReloginRecoveryOverride;

  int get _effectiveHardReloginFailureThreshold {
    final configured = _featureFlags?.hubHardReloginFailureThreshold ?? _hardReloginFailureThresholdOverride;
    return configured.clamp(_hardReloginMinThreshold, _hardReloginMaxThreshold);
  }

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
    _resilienceCoordinator.cancelNegotiatingWatchdog();
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

  Future<void> disconnectForShutdown() async {
    await disconnect();
    _releaseShutdownResources();
  }

  Future<void> disconnect() => _connectionSessionOrchestrator.disconnect();

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
    _proactiveTokenRefreshScheduler.dispose();
    _hubAccessTokenRenewer?.clearAuthBridge();
    _resilienceCoordinator.dispose();
    _persistentRetryCoordinator.dispose();
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

  HubRecoveryDiagnosticsSnapshot get hubRecoveryDiagnostics {
    return HubRecoveryDiagnosticsSnapshot(
      recoveryId: _resilienceCoordinator.recoveryId,
      connectionStatusName: _displayState.status.name,
      hubRecoveryUiHintName: _displayState.hubRecoveryUiHint.name,
      consecutiveReconnectFailures: _hubRecoveryOrchestrator.consecutiveReconnectFailures,
      persistentRetryTickCount: _hubRecoveryOrchestrator.persistentRetryTickCount,
      persistentFailureCount: _hubRecoveryOrchestrator.persistentFailureCount,
      hardReloginAttemptedInCycle: _hubRecoveryOrchestrator.hardReloginAttemptedInCycle,
      lastError: _displayState.error,
    );
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

final class _HubConnectionShutdownPortAdapter implements IHubConnectionShutdownPort {
  const _HubConnectionShutdownPortAdapter(this._connectionProvider);

  final ConnectionProvider _connectionProvider;

  @override
  Future<void> disconnectForShutdown() => _connectionProvider.disconnectForShutdown();
}
