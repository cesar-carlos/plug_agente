import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/ports/hub_recovery_ui_sink.dart';
import 'package:plug_agente/application/ports/i_connection_context_source.dart';
import 'package:plug_agente/application/ports/i_hub_recovery_auth_bridge.dart';
import 'package:plug_agente/application/services/hub_access_token_refresh_gate.dart';
import 'package:plug_agente/application/services/hub_access_token_renewer.dart';
import 'package:plug_agente/application/services/hub_proactive_token_refresh_scheduler.dart';
import 'package:plug_agente/application/services/hub_recovery_orchestrator.dart';
import 'package:plug_agente/application/services/hub_recovery_runtime_dependencies.dart';
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
import 'package:plug_agente/core/di/hub_recovery_orchestrator_factory.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:plug_agente/domain/value_objects/hub_recovery_diagnostics_snapshot.dart';
import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';
import 'package:plug_agente/presentation/adapters/hub_recovery_auth_bridge.dart';
import 'package:plug_agente/presentation/adapters/presentation_connection_context_source.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:result_dart/result_dart.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  negotiating,
  connected,
  reconnecting,
  error,
}

class ConnectionProvider extends ChangeNotifier implements HubRecoveryUiSink {
  ConnectionProvider(
    this._connectToHubUseCase,
    this._testDbConnectionUseCase,
    this._checkOdbcDriverUseCase, {
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
    HubResilienceCoordinator? hubResilienceCoordinator,
    HubAccessTokenRefreshGate? hubAccessTokenRefreshGate,
    HubAccessTokenRenewer? hubAccessTokenRenewer,
  }) : _checkHubAvailabilityUseCase = checkHubAvailabilityUseCase,
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
       _hubAccessTokenRenewer = hubAccessTokenRenewer {
    _connectionTrackingState = HubConnectionTrackingState();
    _contextSource =
        connectionContextSource ??
        PresentationConnectionContextSource(
          trackingState: _connectionTrackingState,
          authProvider: () => _authProvider,
          configProvider: () => _configProvider,
        );
    _hubRecoveryAuthBridge = hubRecoveryAuthBridge ?? _buildRecoveryAuthBridge(_hubSessionCoordinator, _authProvider);
    _hubAccessTokenRefreshGate = hubAccessTokenRefreshGate ?? HubAccessTokenRefreshGate(
      minInterval: hubTokenRefreshMinInterval ?? ConnectionConstants.hubTokenRefreshMinInterval,
    );
    _resilienceCoordinator =
        hubResilienceCoordinator ??
        HubResilienceCoordinator(
          environment: HubResilienceEnvironment(
            isDisconnectRequested: () => _isDisconnectRequested,
            isReconnecting: () => _isReconnecting,
            hasPersistentRetryTimer: () => _hubPersistentRetryTimer != null,
            persistentRetryInFlight: () => _persistentRetryInFlight,
            isNegotiating: () => _status == ConnectionStatus.negotiating,
            resolveConnectionContext: _contextSource.resolveConnectionContext,
            lastAgentId: () => _connectionTrackingState.lastAgentId,
            syncTransportResilienceLogContext: _transportClient.setResilienceLogContext,
            handleReconnectionNeeded: _handleReconnectionNeeded,
            onNegotiatingWatchdogTimeoutWithoutContext: _onNegotiatingWatchdogTimeoutWithoutContext,
            onNegotiatingWatchdogTimeoutWithContext: _onNegotiatingWatchdogTimeoutWithContext,
          ),
          connectionContextSource: _contextSource,
          recoveryAuthBridge: _hubRecoveryAuthBridge,
          tokenRefreshGate: _hubAccessTokenRefreshGate,
          capabilitiesNegotiationWatchdogOverride: capabilitiesNegotiationWatchdogOverride,
          random: random,
        );
    _hubRecoveryOrchestrator = createHubRecoveryOrchestrator(
      initialReconnectDelay: initialReconnectDelay,
      maxReconnectDelay: maxReconnectDelay,
      random: random,
      runtime: HubRecoveryRuntimeDependencies(
        resilienceCoordinator: _resilienceCoordinator,
        contextSource: _contextSource,
        checkHubAvailability: _checkHubAvailabilityUseCase,
        uiSink: this,
        resilienceLogPrefix: _resilienceLogPrefix,
        isDisconnectRequested: () => _isDisconnectRequested,
        tryRefreshToken: _tryRefreshToken,
        attemptReconnect: _attemptReconnect,
        disconnectTransportForRecovery: _disconnectTransportForRecovery,
        executeHardRelogin: _executeHardRelogin,
        bumpPersistentReconnectFailure: _bumpPersistentReconnectFailure,
        isStatusError: () => _status == ConnectionStatus.error,
        cancelPersistentRetryTimer: _cancelPersistentRetryTimer,
      ),
    );
    _proactiveTokenRefreshScheduler = HubProactiveTokenRefreshScheduler(
      refreshBeforeExpiry: ConnectionConstants.hubAccessTokenProactiveRefreshMargin,
      accessTokenProvider: _resolveProactiveRefreshAccessToken,
      onRefreshDue: _runProactiveTokenRefresh,
    );
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
  final CheckHubAvailability? _checkHubAvailabilityUseCase;
  final HubSessionCoordinator? _hubSessionCoordinator;
  final ConnectToHub _connectToHubUseCase;
  final TestDbConnection _testDbConnectionUseCase;
  final CheckOdbcDriver _checkOdbcDriverUseCase;
  AuthProvider? _authProvider;
  ConfigProvider? _configProvider;
  IHubRecoveryAuthBridge? _hubRecoveryAuthBridge;
  late final HubConnectionTrackingState _connectionTrackingState;
  late final IConnectionContextSource _contextSource;
  final ITransportClient _transportClient;
  final HubResilienceConfig? _hubResilience;
  final FeatureFlags? _featureFlags;

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
      _startProactiveTokenRefreshSchedule();
    }
  }

  ConnectionStatus _status = ConnectionStatus.disconnected;
  String _error = '';
  bool _isDbConnected = false;
  bool _isReconnecting = false;
  bool _isCheckingDriver = false;
  bool _isDisconnectRequested = false;
  Timer? _hubPersistentRetryTimer;
  bool _persistentRetryInFlight = false;
  int _reconnectQuietFailureLogCount = 0;
  HubRecoveryUiHint _hubRecoveryUiHint = HubRecoveryUiHint.none;
  late final HubAccessTokenRefreshGate _hubAccessTokenRefreshGate;
  final HubAccessTokenRenewer? _hubAccessTokenRenewer;
  late final HubResilienceCoordinator _resilienceCoordinator;
  late final HubRecoveryOrchestrator _hubRecoveryOrchestrator;
  late final HubProactiveTokenRefreshScheduler _proactiveTokenRefreshScheduler;

  static const Duration _defaultInitialReconnectDelay = Duration(
    seconds: AppConstants.reconnectIntervalSeconds,
  );
  static const Duration _defaultMaxReconnectDelay = Duration(seconds: 60);

  /// Burst-mode token refresh cadence: trigger a refresh after every Nth
  /// failed reconnect attempt. MUST be `<= _defaultMaxReconnectAttempts` so the
  /// refresh actually fires inside the burst window (otherwise the periodic
  /// check `attempt % N == 0` becomes dead code).
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

  ConnectionStatus get status => _status;
  String get error => _error;
  bool get isDbConnected => _isDbConnected;
  String? get activeConfigId => _connectionTrackingState.lastConfigId;

  HubRecoveryUiHint get hubRecoveryUiHint => _hubRecoveryUiHint;

  @override
  void setHubRecoveryUiHint(HubRecoveryUiHint hint) {
    if (_hubRecoveryUiHint == hint) {
      return;
    }
    _hubRecoveryUiHint = hint;
    notifyListeners();
  }

  @override
  void clearHubRecoveryUiHint() {
    setHubRecoveryUiHint(HubRecoveryUiHint.none);
  }

  /// Updates the DB status chip shown next to hub status when connectivity is
  /// proven elsewhere (e.g. successful Playground query or test from Playground).
  void setDbConnectionIndicator(bool connected) {
    if (_isDbConnected == connected) {
      return;
    }
    _isDbConnected = connected;
    notifyListeners();
  }

  bool get isConnected => _status == ConnectionStatus.connected;

  /// True while an internal recovery handler runs, or when the hub link is in a
  /// reconnecting state (including Socket.IO lifecycle).
  bool get isReconnecting => _isReconnecting || _status == ConnectionStatus.reconnecting;
  bool get isConnectingOrNegotiating =>
      _status == ConnectionStatus.connecting || _status == ConnectionStatus.negotiating;
  bool get isCheckingDriver => _isCheckingDriver;

  String _resilienceLogPrefix() => _resilienceCoordinator.resilienceLogPrefix();

  void _onNegotiatingWatchdogTimeoutWithoutContext({required int timeoutMs}) {
    _resilienceCoordinator.cancelNegotiatingWatchdog();
    final failure = domain_errors.ConnectionFailure.withContext(
      message: 'Protocol negotiation timed out. Reconnect to the hub or verify the server is responding.',
      context: {
        'operation': 'negotiating_watchdog',
        'timeout_ms': timeoutMs,
      },
    );
    _status = ConnectionStatus.error;
    _error = failure.toDisplayMessage();
    notifyListeners();
  }

  void _onNegotiatingWatchdogTimeoutWithContext() {
    setHubRecoveryUiHint(HubRecoveryUiHint.negotiationTimedOut);
    _status = ConnectionStatus.reconnecting;
    _error = '';
    notifyListeners();
  }

  void _enterNegotiatingState() {
    _status = ConnectionStatus.negotiating;
    _error = '';
    _resilienceCoordinator.armNegotiatingWatchdog();
  }

  void _kickHubTransportRecovery({required String trigger}) {
    _resilienceCoordinator.kickHubTransportRecovery(trigger: trigger);
  }

  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? configId,
    String? authToken,
    bool recoverOnFailure = false,
  }) async {
    _cancelPersistentRetryTimer();
    _hubRecoveryOrchestrator.resetForUserConnect();
    _connectionTrackingState.sessionAuthInvalid = false;
    _resilienceCoordinator.resetAuthRecoveryState();
    _reconnectQuietFailureLogCount = 0;
    _resilienceCoordinator.invalidateHubConnectEpoch();
    _resilienceCoordinator.clearResilienceRecovery();
    clearHubRecoveryUiHint();
    _isDisconnectRequested = false;
    final resolvedConfigId = _contextSource.resolveActiveConfigId(configId);
    if (_connectionTrackingState.lastConfigId != null && _connectionTrackingState.lastConfigId != resolvedConfigId) {
      _connectionTrackingState.lastAuthToken = null;
    }
    _connectionTrackingState.lastConfigId = resolvedConfigId;
    _connectionTrackingState.lastServerUrl = serverUrl;
    _connectionTrackingState.lastAgentId = agentId;
    _connectionTrackingState.lastAuthToken = _normalizeToken(authToken) ?? _connectionTrackingState.lastAuthToken;

    _resilienceCoordinator.cancelNegotiatingWatchdog();
    _status = ConnectionStatus.connecting;
    _error = '';
    notifyListeners();

    _configureTransportCallbacks();

    final result = await _resilienceCoordinator.runSerializedHubConnect(
      () => _connectToHubUseCase(
        serverUrl,
        agentId,
        authToken: authToken,
      ),
    );

    final finalResult = result.fold<Result<void>>(
      (_) {
        if (_isDisconnectRequested) {
          return const Success(unit);
        }
        _cancelPersistentRetryTimer();
        clearHubRecoveryUiHint();
        _enterNegotiatingState();
        AppLogger.info('Connected to hub transport; waiting for protocol negotiation');
        return const Success(unit);
      },
      (failure) {
        if (_isDisconnectRequested) {
          _status = ConnectionStatus.disconnected;
          return Failure(failure);
        }
        if (_isReconnecting || _status == ConnectionStatus.reconnecting) {
          AppLogger.warning(
            'Initial connect failure ignored because hub recovery is already in progress: ${failure.toDisplayMessage()}',
            failure.toTechnicalMessage(),
          );
          return Failure(failure);
        }
        if (recoverOnFailure && _contextSource.resolveConnectionContext() != null) {
          _resilienceCoordinator.beginResilienceRecovery();
          _status = ConnectionStatus.reconnecting;
          _error = '';
          clearHubRecoveryUiHint();
          AppLogger.warning(
            'Initial hub connect failed; entering persistent recovery: ${failure.toDisplayMessage()}',
            failure.toTechnicalMessage(),
          );
          _startPersistentRetry();
          return Failure(failure);
        }
        _status = ConnectionStatus.error;
        _error = failure.toDisplayMessage();
        clearHubRecoveryUiHint();
        AppLogger.error(
          'Failed to connect to hub: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
        return Failure(failure);
      },
    );

    notifyListeners();
    return finalResult;
  }

  void startPersistentHubRecovery({
    required String configId,
    required String serverUrl,
    required String agentId,
    String? authToken,
  }) {
    _cancelPersistentRetryTimer();
    _hubRecoveryOrchestrator.resetForStartupPersistentRecovery();
    _connectionTrackingState.sessionAuthInvalid = false;
    _resilienceCoordinator.resetAuthRecoveryState();
    _reconnectQuietFailureLogCount = 0;
    _isDisconnectRequested = false;
    _connectionTrackingState.lastConfigId = configId;
    _connectionTrackingState.lastServerUrl = serverUrl;
    _connectionTrackingState.lastAgentId = agentId;
    _connectionTrackingState.lastAuthToken = _normalizeToken(authToken);

    _configureTransportCallbacks();
    _resilienceCoordinator.beginResilienceRecovery();
    _status = ConnectionStatus.reconnecting;
    _error = '';
    clearHubRecoveryUiHint();
    AppLogger.warning(
      'resilience: ${_resilienceLogPrefix()}persistent_retry event=startup_recovery_started '
      'agent_id=$agentId',
    );
    notifyListeners();
    _startPersistentRetry();
  }

  void _configureTransportCallbacks() {
    _transportClient.setOnTokenExpired(_handleTokenExpired);
    _transportClient.setOnReconnectionNeeded(
      () => unawaited(_resilienceCoordinator.scheduleExclusiveRecovery()),
    );
    _transportClient.setOnHubLifecycle(_handleHubLifecycle);
  }

  Future<void> disconnect() async {
    _isDisconnectRequested = true;
    _hubAccessTokenRenewer?.clearAuthBridge();
    _resilienceCoordinator.invalidateHubConnectEpoch();
    _resilienceCoordinator.cancelNegotiatingWatchdog();
    _resilienceCoordinator.clearResilienceRecovery();
    clearHubRecoveryUiHint();
    _cancelPersistentRetryTimer();
    _cancelProactiveTokenRefreshSchedule();
    _hubRecoveryOrchestrator.resetForDisconnect();
    _resilienceCoordinator.resetAuthRecoveryState();
    _reconnectQuietFailureLogCount = 0;
    _connectionTrackingState.lastAuthToken = null;
    await _transportClient.disconnect();
    _status = ConnectionStatus.disconnected;
    _error = '';
    notifyListeners();

    AppLogger.info('Disconnected from hub');
  }

  Future<Result<bool>> testDbConnection(
    String connectionString, {
    bool recordGlobalError = true,
  }) async {
    final result = await _testDbConnectionUseCase(connectionString);

    result.fold(
      (bool isConnected) {
        setDbConnectionIndicator(isConnected);
        if (isConnected) {
          AppLogger.info('Database connection test successful');
        } else {
          AppLogger.warning('Database connection test failed');
        }
      },
      (Object failure) {
        setDbConnectionIndicator(false);
        if (recordGlobalError) {
          _error = failure.toDisplayMessage();
        }
        AppLogger.error(
          'Database connection test failed: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
      },
    );

    notifyListeners();
    return result;
  }

  void clearError() {
    _error = '';
    notifyListeners();
  }

  Future<Result<bool>> checkOdbcDriver(String driverName) async {
    _isCheckingDriver = true;
    _error = '';
    notifyListeners();

    final result = await _checkOdbcDriverUseCase(driverName);

    result.fold(
      (isInstalled) {
        if (isInstalled) {
          AppLogger.info('ODBC driver "$driverName" is installed');
        } else {
          AppLogger.warning('ODBC driver "$driverName" is not installed');
        }
      },
      (failure) {
        _error = failure.toDisplayMessage();
        AppLogger.error(
          'Failed to check ODBC driver: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
      },
    );

    _isCheckingDriver = false;
    notifyListeners();
    return result;
  }

  Future<void> _handleTokenExpired() async {
    if (_isDisconnectRequested) {
      return;
    }

    // During hub recovery burst/persistent retry, `_isReconnecting` is true but we still
    // need to refresh - otherwise `_handleConnectionError` fires `_onTokenExpired` and we
    // never rotate JWT until user logs out/in manually.
    if (_isReconnecting) {
      final context = _contextSource.resolveConnectionContext();
      if (context != null) {
        AppLogger.warning(
          'Hub reported authentication failure during reconnect; refreshing token',
        );
        AppLogger.debug(
          'resilience: ${_resilienceLogPrefix()}token_refresh event=during_reconnect_burst '
          'agent_id=${context.agentId}',
        );
        await _tryRefreshToken(context);
      }
      return;
    }

    _isReconnecting = true;
    _hubRecoveryOrchestrator.resetHardReloginCycle();
    _status = ConnectionStatus.reconnecting;
    _error = '';
    AppLogger.warning('Token expired, attempting refresh...');
    notifyListeners();

    try {
      _resilienceCoordinator.beginResilienceRecovery();
      await _transportClient.disconnect();
      _configureTransportCallbacks();

      final context = _contextSource.resolveConnectionContext();
      if (context == null) {
        _resilienceCoordinator.clearResilienceRecovery();
        _status = ConnectionStatus.error;
        _error = 'Connection context unavailable for token refresh';
        clearHubRecoveryUiHint();
        AppLogger.error('Cannot refresh token without connection context');
      } else {
        final refreshResult = await _tryRefreshToken(context);
        final reconnectToken = await _resolveReconnectTokenAfterRefresh(context, refreshResult);
        if (reconnectToken == null) {
          _resilienceCoordinator.clearResilienceRecovery();
          _status = ConnectionStatus.error;
          _error = 'Failed to refresh authentication token';
          clearHubRecoveryUiHint();
          AppLogger.error('Token refresh failed during reconnect policy');
        } else {
          final connected = await _attemptReconnect(
            context.serverUrl,
            context.agentId,
            authToken: reconnectToken,
          );
          if (connected) {
            AppLogger.info('Reconnected with refreshed token successfully');
          } else if (!_isDisconnectRequested) {
            AppLogger.warning(
              'Single reconnect with refreshed token failed; escalating to recovery burst',
            );
            final recovered = await _recoverConnection(context);
            if (!recovered && !_isDisconnectRequested) {
              AppLogger.warning(
                'Recovery burst exhausted after token refresh; starting persistent retry',
              );
              _startPersistentRetry();
            }
          }
        }
      }
    } on Exception catch (error, stackTrace) {
      _resilienceCoordinator.clearResilienceRecovery();
      clearHubRecoveryUiHint();
      _status = ConnectionStatus.error;
      final failure = domain_errors.ConnectionFailure.withContext(
        message: 'Failed to refresh token',
        cause: error,
        context: {'operation': 'handleTokenExpired'},
      );
      _error = failure.toDisplayMessage();
      AppLogger.error(
        'Token refresh failed: ${failure.toDisplayMessage()}',
        error,
        stackTrace,
      );
    } finally {
      // Same rationale as `_handleReconnectionNeeded`: an `Error` (not
      // `Exception`) escaping or an early `return` inside the try block must
      // not leave `_isReconnecting=true` and block future recovery cycles.
      _isReconnecting = false;
      notifyListeners();
    }
  }

  Future<void> _handleReconnectionNeeded() async {
    if (_isReconnecting || _isDisconnectRequested) {
      AppLogger.debug(
        'resilience: ${_resilienceLogPrefix()}reconnect event=handler_skipped '
        'reconnecting=$_isReconnecting disconnect_requested=$_isDisconnectRequested',
      );
      return;
    }

    _isReconnecting = true;
    _hubRecoveryOrchestrator.resetHardReloginCycle();
    _status = ConnectionStatus.reconnecting;
    _error = '';
    AppLogger.warning('Reconnection needed after failed attempts');
    notifyListeners();

    try {
      final context = _contextSource.resolveConnectionContext();
      if (context == null) {
        _status = ConnectionStatus.error;
        _error = 'Server URL or Agent ID not available for reconnection';
        clearHubRecoveryUiHint();
        AppLogger.error('Missing server URL or agent ID for reconnection');
      } else {
        _resilienceCoordinator.beginResilienceRecovery();
        AppLogger.info(
          'resilience: ${_resilienceLogPrefix()}reconnect event=full_recovery_started '
          'agent_id=${context.agentId}',
        );
        final connected = await _recoverConnection(
          context,
        );
        if (_isDisconnectRequested) {
          _status = ConnectionStatus.disconnected;
          _error = '';
          AppLogger.info('Reconnection loop cancelled by user disconnect');
          _resilienceCoordinator.clearResilienceRecovery();
          return;
        }
        if (connected) {
          AppLogger.info(
            'resilience: ${_resilienceLogPrefix()}reconnect event=burst_recovery_complete '
            'agent_id=${context.agentId}',
          );
        }
        if (!connected) {
          if (_isDisconnectRequested) {
            _resilienceCoordinator.clearResilienceRecovery();
            return;
          }
          _status = ConnectionStatus.reconnecting;
          _error = '';
          AppLogger.warning('Connection burst recovery exhausted; starting persistent hub retry');
          _startPersistentRetry();
        }
      }
    } on Exception catch (error, stackTrace) {
      _resilienceCoordinator.clearResilienceRecovery();
      clearHubRecoveryUiHint();
      _status = ConnectionStatus.error;
      final failure = domain_errors.ConnectionFailure.withContext(
        message: 'Failed to reconnect to the hub',
        cause: error,
        context: {'operation': 'handleReconnectionNeeded'},
      );
      _error = failure.toDisplayMessage();
      AppLogger.error(
        'Manual reconnection failed: ${failure.toDisplayMessage()}',
        error,
        stackTrace,
      );
    } finally {
      // Must run on every exit path (Exception caught, Error escaping, or
      // early `return` inside the try block). Without `finally`, a user
      // disconnect mid-burst or an unhandled `Error` would leave
      // `_isReconnecting=true`, permanently blocking future recovery attempts.
      _isReconnecting = false;
      notifyListeners();
    }
  }

  Future<void> _disconnectTransportForRecovery() async {
    try {
      final result = await _transportClient.disconnect();
      result.fold(
        (_) {},
        (failure) {
          AppLogger.warning(
            'resilience: ${_resilienceLogPrefix()}transport_disconnect_during_recovery '
            'message=$failure',
          );
        },
      );
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'resilience: ${_resilienceLogPrefix()}transport_disconnect_during_recovery event=exception',
        error,
        stackTrace,
      );
    } finally {
      _configureTransportCallbacks();
    }
  }

  Future<String?> _executeHardRelogin(
    HubConnectionContext context, {
    required String logSummary,
    bool ignoreCooldown = false,
  }) async {
    setHubRecoveryUiHint(HubRecoveryUiHint.signingIn);
    final result = await _resilienceCoordinator.executeHardRelogin(
      context,
      logSummary: logSummary,
      hardReloginCooldown: _effectiveHubHardReloginCooldown,
      ignoreCooldown: ignoreCooldown,
    );

    switch (result.outcome) {
      case HardReloginOutcome.skippedCooldown:
        clearHubRecoveryUiHint();
        return null;
      case HardReloginOutcome.authBridgeUnavailable:
        _resilienceCoordinator.clearResilienceRecovery();
        _status = ConnectionStatus.error;
        _error = 'Authentication provider unavailable for automatic relogin';
        _cancelPersistentRetryTimer();
        clearHubRecoveryUiHint();
        return null;
      case HardReloginOutcome.failed:
        _connectionTrackingState.lastAuthToken = null;
        _connectionTrackingState.sessionAuthInvalid = true;
        _status = ConnectionStatus.error;
        _error = result.failureMessage ?? 'Automatic relogin failed';
        _cancelPersistentRetryTimer();
        _resilienceCoordinator.clearResilienceRecovery();
        clearHubRecoveryUiHint();
        return null;
      case HardReloginOutcome.success:
        _connectionTrackingState.sessionAuthInvalid = false;
        _hubRecoveryOrchestrator.resetConsecutiveFailuresAfterHardReloginSuccess();
        return _connectionTrackingState.lastAuthToken = result.token;
    }
  }

  Future<bool> _recoverConnection(
    HubConnectionContext context, {
    bool proactiveHardReloginBeforeSocket = false,
  }) {
    return _hubRecoveryOrchestrator.runBurstRecovery(
      context,
      proactiveHardReloginBeforeSocket: proactiveHardReloginBeforeSocket,
      effectiveHardReloginRecoveryEnabled: _effectiveHardReloginRecoveryEnabled,
      hasAuthBridge: _hubRecoveryAuthBridge != null,
      maxReconnectAttempts: _maxReconnectAttempts,
      tokenRefreshIntervalAttempts: _tokenRefreshIntervalAttempts,
      recoveryEnabled: _effectiveHardReloginRecoveryEnabled,
      hardReloginFailureThreshold: _effectiveHardReloginFailureThreshold,
    );
  }

  Future<bool> _attemptReconnect(
    String serverUrl,
    String agentId, {
    String? authToken,
    bool recordErrorMessage = true,
  }) async {
    return _resilienceCoordinator.runSerializedHubConnect<bool>(
      () async {
        if (_isDisconnectRequested) {
          return false;
        }
        if (_status == ConnectionStatus.reconnecting || _isReconnecting) {
          setHubRecoveryUiHint(HubRecoveryUiHint.connectingSocket);
        }
        final result = await _connectToHubUseCase(
          serverUrl,
          agentId,
          authToken: authToken,
        );

        return result.fold(
          (_) {
            _cancelPersistentRetryTimer();
            _hubRecoveryOrchestrator.noteTransportConnectSuccessDuringRecovery();
            _connectionTrackingState.sessionAuthInvalid = false;
            _reconnectQuietFailureLogCount = 0;
            _enterNegotiatingState();
            _connectionTrackingState.lastServerUrl = serverUrl;
            _connectionTrackingState.lastAgentId = agentId;
            if (authToken != null && authToken.trim().isNotEmpty) {
              _connectionTrackingState.lastAuthToken = authToken.trim();
            }
            AppLogger.info(
              'resilience: ${_resilienceLogPrefix()}hub_connect event=transport_succeeded agent_id=$agentId',
            );
            clearHubRecoveryUiHint();
            return true;
          },
          (Object failure) {
            _hubRecoveryOrchestrator.noteTransportConnectFailureDuringRecovery();
            _status = ConnectionStatus.reconnecting;
            _error = recordErrorMessage ? failure.toDisplayMessage() : '';
            if (recordErrorMessage) {
              AppLogger.warning(
                'Reconnection attempt failed: ${failure.toDisplayMessage()}',
                failure.toTechnicalMessage(),
              );
            } else {
              _reconnectQuietFailureLogCount++;
              const stride = ConnectionConstants.hubReconnectFailureLogThrottleStride;
              if (_reconnectQuietFailureLogCount == 1 || _reconnectQuietFailureLogCount % stride == 0) {
                AppLogger.warning(
                  'resilience: ${_resilienceLogPrefix()}reconnect event=attempt_failed_throttled '
                  'count=$_reconnectQuietFailureLogCount stride=$stride '
                  'display=${failure.toDisplayMessage()}',
                  failure.toTechnicalMessage(),
                );
              }
            }
            clearHubRecoveryUiHint();
            return false;
          },
        );
      },
      staleResult: false,
    );
  }

  void _bumpPersistentReconnectFailure(
    HubConnectionContext context, {
    required String reason,
  }) {
    if (_effectiveHubPersistentRetryMaxFailedTicks <= 0) {
      return;
    }
    _hubRecoveryOrchestrator.bumpPersistentFailure();
    AppLogger.info(
      'resilience: ${_resilienceLogPrefix()}hub_persistent_retry_failure '
      'count=${_hubRecoveryOrchestrator.persistentFailureCount} '
      'max=$_effectiveHubPersistentRetryMaxFailedTicks '
      'reason=$reason '
      'agent_id=${context.agentId}',
    );
    if (_hubRecoveryOrchestrator.persistentFailureCount >= _effectiveHubPersistentRetryMaxFailedTicks) {
      _cancelPersistentRetryTimer();
      _status = ConnectionStatus.error;
      _error = ConnectionConstants.hubPersistentRetryExhaustedMessage;
      AppLogger.warning(
        'resilience: ${_resilienceLogPrefix()}persistent_retry event=exhausted '
        'failures=${_hubRecoveryOrchestrator.persistentFailureCount} '
        'max=$_effectiveHubPersistentRetryMaxFailedTicks '
        'agent_id=${context.agentId}',
      );
      _resilienceCoordinator.clearResilienceRecovery();
      clearHubRecoveryUiHint();
      notifyListeners();
    }
  }

  void _handleHubLifecycle(HubLifecycleNotification notification) {
    if (_isDisconnectRequested) {
      return;
    }
    switch (notification) {
      case HubTransportDisconnected(:final reason):
        if (_status == ConnectionStatus.disconnected) {
          return;
        }
        _resilienceCoordinator.beginResilienceRecovery();
        final serverInitiated = isHubIoServerInitiatedDisconnect(reason);
        final disconnectLine =
            'resilience: ${_resilienceLogPrefix()}hub_transport event=socket_disconnected '
            'kind=${serverInitiated ? "io_server_disconnect" : "client_or_network"} '
            'reason=${reason ?? "unknown"} '
            'agent_id=${_connectionTrackingState.lastAgentId ?? "?"}';
        AppLogger.debug(disconnectLine);
        _status = ConnectionStatus.reconnecting;
        _error = '';
        notifyListeners();
        _kickHubTransportRecovery(trigger: 'hub_transport_disconnected');
        if (_hubPersistentRetryTimer != null && !_persistentRetryInFlight) {
          unawaited(_persistentRetryTick());
        }
      case HubTransportReconnectAttempt(:final attemptNumber):
        AppLogger.info(
          'resilience: ${_resilienceLogPrefix()}hub_socket_reconnect_attempt attempt=$attemptNumber '
          'status=${_status.name}',
        );
        if (_status == ConnectionStatus.connected || _status == ConnectionStatus.negotiating) {
          _status = ConnectionStatus.reconnecting;
          _error = '';
          notifyListeners();
        }
      case HubProtocolReady():
        if (_status != ConnectionStatus.negotiating &&
            _status != ConnectionStatus.reconnecting &&
            _status != ConnectionStatus.connected) {
          AppLogger.debug(
            'resilience: ${_resilienceLogPrefix()}hub_transport event=protocol_ready_ignored '
            'status=${_status.name} agent_id=${_connectionTrackingState.lastAgentId ?? "?"}',
          );
          return;
        }
        AppLogger.info(
          'resilience: ${_resilienceLogPrefix()}hub_transport event=protocol_ready '
          'agent_id=${_connectionTrackingState.lastAgentId ?? "?"}',
        );
        _resilienceCoordinator.cancelNegotiatingWatchdog();
        _resilienceCoordinator.clearResilienceRecovery();
        _cancelPersistentRetryTimer();
        clearHubRecoveryUiHint();
        _status = ConnectionStatus.connected;
        // Clear the burst-recovery flag so isReconnecting reflects the
        // connected state immediately, without waiting for the async
        // _handleReconnectionNeeded to return and clear it at its finally.
        _isReconnecting = false;
        _error = '';
        _startProactiveTokenRefreshSchedule();
        notifyListeners();
      case HubTransportAutoReconnectSucceeded():
        if (_status != ConnectionStatus.negotiating &&
            _status != ConnectionStatus.reconnecting &&
            _status != ConnectionStatus.connected) {
          AppLogger.debug(
            'resilience: ${_resilienceLogPrefix()}hub_transport event=auto_reconnect_capabilities_ok_ignored '
            'status=${_status.name} agent_id=${_connectionTrackingState.lastAgentId ?? "?"}',
          );
          return;
        }
        AppLogger.info(
          'resilience: ${_resilienceLogPrefix()}hub_transport event=auto_reconnect_capabilities_ok '
          'agent_id=${_connectionTrackingState.lastAgentId ?? "?"}',
        );
        _resilienceCoordinator.cancelNegotiatingWatchdog();
        _resilienceCoordinator.clearResilienceRecovery();
        _cancelPersistentRetryTimer();
        clearHubRecoveryUiHint();
        _status = ConnectionStatus.connected;
        _isReconnecting = false;
        _error = '';
        _startProactiveTokenRefreshSchedule();
        notifyListeners();
    }
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

  void _startProactiveTokenRefreshSchedule() {
    _proactiveTokenRefreshScheduler.reschedule();
  }

  void _cancelProactiveTokenRefreshSchedule() {
    _proactiveTokenRefreshScheduler.cancel();
  }

  Future<void> _runProactiveTokenRefresh() async {
    if (_isDisconnectRequested || !isConnected) {
      return;
    }

    final context = _contextSource.resolveConnectionContext();
    if (context == null) {
      return;
    }

    AppLogger.info('Proactive hub access token refresh due');
    final refreshResult = await _tryRefreshToken(context);
    switch (refreshResult.kind) {
      case TokenRefreshResultKind.refreshed:
        AppLogger.info('Proactive hub access token refresh succeeded');
        final token = refreshResult.token;
        if (token != null && token.isNotEmpty) {
          await _reconnectTransportWithRefreshedToken(context, token);
        }
      case TokenRefreshResultKind.skippedByCooldown:
        AppLogger.debug('Proactive hub access token refresh skipped (cooldown)');
      case TokenRefreshResultKind.transientFailure:
        AppLogger.warning('Proactive hub access token refresh transient failure');
        _kickHubTransportRecovery(trigger: 'proactive_refresh_transient');
      case TokenRefreshResultKind.terminalFailure:
        AppLogger.warning('Proactive hub access token refresh failed');
        if (!_isDisconnectRequested) {
          _status = ConnectionStatus.error;
          _error = _hubRecoveryAuthBridge == null
              ? 'Failed to refresh authentication token'
              : _authProvider?.error ?? 'Failed to refresh authentication token';
          _kickHubTransportRecovery(trigger: 'proactive_refresh_terminal');
          notifyListeners();
        }
    }

    if (!_isDisconnectRequested && isConnected) {
      _startProactiveTokenRefreshSchedule();
    }
  }

  Future<String?> _resolveReconnectTokenAfterRefresh(
    HubConnectionContext context,
    TokenRefreshResult refreshResult,
  ) async {
    switch (refreshResult.kind) {
      case TokenRefreshResultKind.refreshed:
        return refreshResult.token;
      case TokenRefreshResultKind.skippedByCooldown:
        await _hubAccessTokenRefreshGate.waitForCooldownOrInFlight();
        final retry = await _tryRefreshToken(context);
        if (retry.kind == TokenRefreshResultKind.refreshed) {
          return retry.token;
        }
        if (_connectionTrackingState.sessionAuthInvalid) {
          return null;
        }
        return _contextSource.resolveAuthTokenForReconnect();
      case TokenRefreshResultKind.transientFailure:
        return _contextSource.resolveAuthTokenForReconnect();
      case TokenRefreshResultKind.terminalFailure:
        return null;
    }
  }

  Future<void> _reconnectTransportWithRefreshedToken(
    HubConnectionContext context,
    String token,
  ) async {
    if (_isDisconnectRequested || !isConnected) {
      return;
    }
    try {
      await _transportClient.disconnect();
      _configureTransportCallbacks();
      await _attemptReconnect(
        context.serverUrl,
        context.agentId,
        authToken: token,
        recordErrorMessage: false,
      );
    } on Exception catch (error, stackTrace) {
      AppLogger.warning(
        'Proactive refresh reconnect failed: $error',
        error,
        stackTrace,
      );
      _kickHubTransportRecovery(trigger: 'proactive_refresh_reconnect');
    }
  }

  void _cancelPersistentRetryTimer() {
    _hubPersistentRetryTimer?.cancel();
    _hubPersistentRetryTimer = null;
  }

  void _startPersistentRetry() {
    _cancelPersistentRetryTimer();
    _hubRecoveryOrchestrator.resetPersistentRetryCounters();
    final ctx = _contextSource.resolveConnectionContext();
    AppLogger.warning(
      'resilience: ${_resilienceLogPrefix()}persistent_retry event=started '
      'interval_ms=${_effectiveHubPersistentRetryInterval.inMilliseconds} '
      'max_failed_ticks=$_effectiveHubPersistentRetryMaxFailedTicks '
      'agent_id=${ctx?.agentId ?? "?"}',
    );
    unawaited(_persistentRetryTick());
    _hubPersistentRetryTimer = Timer.periodic(_effectiveHubPersistentRetryInterval, (_) {
      unawaited(_persistentRetryTick());
    });
  }

  Future<void> _persistentRetryTick() async {
    if (_persistentRetryInFlight) {
      return;
    }
    _persistentRetryInFlight = true;
    try {
      await _hubRecoveryOrchestrator.runPersistentTick(
        tokenRefreshIntervalAttempts: _tokenRefreshIntervalAttempts,
        recoveryEnabled: _effectiveHardReloginRecoveryEnabled,
        hardReloginFailureThreshold: _effectiveHardReloginFailureThreshold,
      );
    } finally {
      _persistentRetryInFlight = false;
    }
  }

  @override
  void dispose() {
    _proactiveTokenRefreshScheduler.dispose();
    _hubAccessTokenRenewer?.clearAuthBridge();
    _resilienceCoordinator.dispose();
    _cancelPersistentRetryTimer();
    clearHubRecoveryUiHint();
    super.dispose();
  }

  Future<TokenRefreshResult> _tryRefreshToken(HubConnectionContext context) async {
    final result = await _resilienceCoordinator.tryRefreshToken(context);
    switch (result.kind) {
      case TokenRefreshResultKind.refreshed:
        _connectionTrackingState.sessionAuthInvalid = false;
        _connectionTrackingState.lastAuthToken = result.token;
        if (!_isDisconnectRequested && isConnected) {
          _startProactiveTokenRefreshSchedule();
        }
      case TokenRefreshResultKind.terminalFailure:
        _connectionTrackingState.lastAuthToken = null;
        _connectionTrackingState.sessionAuthInvalid = true;
      case TokenRefreshResultKind.skippedByCooldown:
      case TokenRefreshResultKind.transientFailure:
        break;
    }
    return result;
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
      connectionStatusName: _status.name,
      hubRecoveryUiHintName: _hubRecoveryUiHint.name,
      consecutiveReconnectFailures: _hubRecoveryOrchestrator.consecutiveReconnectFailures,
      persistentRetryTickCount: _hubRecoveryOrchestrator.persistentRetryTickCount,
      persistentFailureCount: _hubRecoveryOrchestrator.persistentFailureCount,
      hardReloginAttemptedInCycle: _hubRecoveryOrchestrator.hardReloginAttemptedInCycle,
      lastError: _error,
    );
  }
}
