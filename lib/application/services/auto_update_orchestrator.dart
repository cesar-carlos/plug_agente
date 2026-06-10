import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:plug_agente/application/observability/i_auto_update_diagnostics_gateway.dart';
import 'package:plug_agente/application/observability/i_auto_update_metrics_collector.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/observability/update_check_id_recorder.dart';
import 'package:plug_agente/application/repositories/degraded_update_preferences_repository.dart';
import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/application/repositories/update_preferences_repository.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator_options.dart';
import 'package:plug_agente/application/services/auto_updater_gateway.dart';
import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/retry_policy.dart';
import 'package:plug_agente/application/services/silent_update_coordinator.dart';
import 'package:plug_agente/application/services/silent_update_coordinator_options.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/application/services/updater_event.dart';
import 'package:plug_agente/application/services/user_initiated_apply_failure.dart';
import 'package:plug_agente/application/services/win_sparkle_background_check_service.dart';
import 'package:plug_agente/application/services/win_sparkle_manual_check_service.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/runtime/i_uac_detector.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

export 'auto_updater_gateway.dart';

/// Orchestrates WinSparkle (manual/background) and the silent update path.
///
/// Manual and background WinSparkle flows delegate to dedicated services;
/// the silent update cycle is fully delegated to [SilentUpdateCoordinator].
class AutoUpdateOrchestrator implements IAutoUpdateOrchestrator {
  AutoUpdateOrchestrator(
    this._capabilities, {
    AutoUpdateOrchestratorOptions? options,
    SilentUpdateCoordinatorOptions? silentOptions,
    IAutoUpdaterGateway? updaterGateway,
    IAppcastProbeService? appcastProbeService,
    ISilentUpdateInstaller? silentUpdateInstaller,
    IAppSettingsStore? settingsStore,
    IUpdatePreferencesRepository? updatePreferencesRepository,
    IAutoUpdateMetricsCollector? metricsCollector,
    CloseApplicationForSilentUpdate? closeApplicationForSilentUpdate,
    Future<void> Function()? allowQuitForUpdate,
    Duration? manualTriggerTimeout,
    Duration? manualCompletionTimeout,
    int? timeoutCircuitThreshold,
    Duration? timeoutCircuitCooldown,
    int? backgroundRetryLimit,
    Duration? backgroundRetryBaseDelay,
    int? automaticFailureCooldownThreshold,
    Duration? automaticFailureCooldown,
    Duration? helperWaitDuration,
    Duration Function()? automaticBootJitterProvider,
    Duration? lateCallbackDrainWindow,
    UpdateCheckIdRecorder? checkIdRecorder,
    ISilentUpdateCoordinator? silentUpdateCoordinator,
    Duration? backgroundTriggerTimeout,
    double? backgroundRetryJitterFactor,
    Random? random,
    IUacDetector? uacDetector,
    IAutoUpdateDiagnosticsGateway? diagnosticsGateway,
    IPendingSilentUpdateStore? pendingStore,
    ISilentUpdateLauncherStatusReader? launcherStatusReader,
    WinSparkleManualCheckService? manualCheckService,
    WinSparkleBackgroundCheckService? backgroundCheckService,
    DateTime Function()? clock,
  }) : _options = _resolveOptions(
         options: options,
         random: random,
         manualTriggerTimeout: manualTriggerTimeout,
         manualCompletionTimeout: manualCompletionTimeout,
         timeoutCircuitThreshold: timeoutCircuitThreshold,
         timeoutCircuitCooldown: timeoutCircuitCooldown,
         backgroundRetryLimit: backgroundRetryLimit,
         backgroundRetryBaseDelay: backgroundRetryBaseDelay,
         backgroundTriggerTimeout: backgroundTriggerTimeout,
         backgroundRetryJitterFactor: backgroundRetryJitterFactor,
         lateCallbackDrainWindow: lateCallbackDrainWindow,
       ),
       _silentOptions = _resolveSilentOptions(
         silentOptions: silentOptions,
         automaticFailureCooldownThreshold: automaticFailureCooldownThreshold,
         automaticFailureCooldown: automaticFailureCooldown,
         helperWaitDuration: helperWaitDuration,
       ),
       _updaterGateway = updaterGateway ?? AutoUpdaterGateway(),
       _appcastProbeService = appcastProbeService ?? AppcastProbeService(),
       _preferences =
           updatePreferencesRepository ??
           (settingsStore != null ? UpdatePreferencesRepository(settingsStore: settingsStore) : null),
       _metricsCollector = metricsCollector,
       _allowQuitForUpdate = allowQuitForUpdate,
       _checkIdRecorder = checkIdRecorder ?? UpdateCheckIdRecorder(settingsStore: settingsStore) {
    final preferences = _preferences;
    final wiredPreferences = preferences ?? DegradedUpdatePreferencesRepository();
    _manualCheckService =
        manualCheckService ??
        WinSparkleManualCheckService(
          capabilities: _capabilities,
          updaterGateway: _updaterGateway,
          appcastProbeService: _appcastProbeService,
          preferences: wiredPreferences,
          options: _options,
          metricsCollector: metricsCollector,
          diagnosticsGateway: diagnosticsGateway,
          checkIdRecorder: _checkIdRecorder,
          manualTimeoutBreaker: preferences == null
              ? null
              : PersistentCircuitBreaker(
                  persistence: preferences.manualTimeoutCircuitPersistence(),
                  threshold: _options.timeoutCircuitThreshold,
                  cooldown: _options.timeoutCircuitCooldown,
                  logName: 'auto_update_orchestrator',
                  clock: clock,
                ),
          clock: clock,
        );
    _backgroundCheckService =
        backgroundCheckService ??
        WinSparkleBackgroundCheckService(
          updaterGateway: _updaterGateway,
          preferences: wiredPreferences,
          manualCheckService: _manualCheckService,
          options: _options,
          metricsCollector: metricsCollector,
          diagnosticsGateway: diagnosticsGateway,
          checkIdRecorder: _checkIdRecorder,
          clock: clock,
          feedUrlResolver: () => _feedUrl,
          onDiagnosticsChanged: _notifyChanges,
        );
    _silentCoordinator =
        silentUpdateCoordinator ??
        SilentUpdateCoordinator(
          _capabilities,
          () => _feedUrl,
          appcastProbeService: _appcastProbeService,
          silentUpdateInstaller: silentUpdateInstaller,
          updatePreferencesRepository: wiredPreferences,
          settingsStore: settingsStore,
          closeApplicationForSilentUpdate: closeApplicationForSilentUpdate,
          onDiagnosticsChanged: _notifyChanges,
          automaticFailureCooldownThreshold: _silentOptions.automaticFailureCooldownThreshold,
          automaticFailureCooldown: _silentOptions.automaticFailureCooldown,
          helperWaitDuration: _silentOptions.helperWaitDuration,
          bootJitterProvider: automaticBootJitterProvider,
          metricsCollector: metricsCollector,
          diagnosticsGateway: diagnosticsGateway,
          checkIdRecorder: _checkIdRecorder,
          uacDetector: uacDetector,
          pendingStore: pendingStore,
          launcherStatusReader: launcherStatusReader,
          clock: clock,
        );
  }

  final StreamController<void> _changesController = StreamController<void>.broadcast();

  void _notifyChanges() {
    if (_changesController.isClosed) return;
    _changesController.add(null);
  }

  Future<void> dispose() async {
    await _updaterEventsSubscription?.cancel();
    _updaterEventsSubscription = null;
    if (!_changesController.isClosed) {
      await _changesController.close();
    }
  }

  static AutoUpdateOrchestratorOptions _resolveOptions({
    AutoUpdateOrchestratorOptions? options,
    Random? random,
    Duration? manualTriggerTimeout,
    Duration? manualCompletionTimeout,
    int? timeoutCircuitThreshold,
    Duration? timeoutCircuitCooldown,
    int? backgroundRetryLimit,
    Duration? backgroundRetryBaseDelay,
    Duration? backgroundTriggerTimeout,
    double? backgroundRetryJitterFactor,
    Duration? lateCallbackDrainWindow,
  }) {
    final base = options ?? AutoUpdateOrchestratorOptions(random: random);
    final base_ = base.backgroundRetry;
    final hasRetryOverride =
        backgroundRetryLimit != null ||
        backgroundRetryBaseDelay != null ||
        backgroundTriggerTimeout != null ||
        backgroundRetryJitterFactor != null;
    final retry = hasRetryOverride
        ? RetryPolicy(
            attemptLimit: backgroundRetryLimit ?? base_.attemptLimit,
            baseDelay: backgroundRetryBaseDelay ?? base_.baseDelay,
            triggerTimeout: backgroundTriggerTimeout ?? base_.triggerTimeout,
            jitterFactor: backgroundRetryJitterFactor ?? base_.jitterFactor,
            random: random,
          )
        : base_;
    return base.copyWith(
      manualTriggerTimeout: manualTriggerTimeout,
      manualCompletionTimeout: manualCompletionTimeout,
      timeoutCircuitThreshold: timeoutCircuitThreshold,
      timeoutCircuitCooldown: timeoutCircuitCooldown,
      lateCallbackDrainWindow: lateCallbackDrainWindow,
      backgroundRetry: hasRetryOverride ? retry : null,
    );
  }

  static SilentUpdateCoordinatorOptions _resolveSilentOptions({
    SilentUpdateCoordinatorOptions? silentOptions,
    int? automaticFailureCooldownThreshold,
    Duration? automaticFailureCooldown,
    Duration? helperWaitDuration,
  }) {
    final base = silentOptions ?? const SilentUpdateCoordinatorOptions();
    return base.copyWith(
      automaticFailureCooldownThreshold: automaticFailureCooldownThreshold,
      automaticFailureCooldown: automaticFailureCooldown,
      helperWaitDuration: helperWaitDuration,
    );
  }

  final RuntimeCapabilities _capabilities;
  final AutoUpdateOrchestratorOptions _options;
  final SilentUpdateCoordinatorOptions _silentOptions;
  final IAutoUpdaterGateway _updaterGateway;
  final IAppcastProbeService _appcastProbeService;
  final IUpdatePreferencesRepository? _preferences;
  final IAutoUpdateMetricsCollector? _metricsCollector;
  final Future<void> Function()? _allowQuitForUpdate;
  final UpdateCheckIdRecorder _checkIdRecorder;

  late final WinSparkleManualCheckService _manualCheckService;
  late final WinSparkleBackgroundCheckService _backgroundCheckService;
  late final ISilentUpdateCoordinator _silentCoordinator;

  bool _isInitialized = false;
  StreamSubscription<UpdaterEvent>? _updaterEventsSubscription;

  String? get _feedUrl {
    final url = resolveAutoUpdateFeedUrl(environment: AppEnvironment.snapshot());
    if (url.isEmpty) return null;
    return isSparkleFeedUrl(url) ? url : null;
  }

  int _resolveWinSparkleIntervalSeconds() {
    if (automaticSilentUpdatesEnabled) return 0;
    if (!updateNotificationsEnabled) return 0;
    return resolveAutoUpdateCheckIntervalSeconds(environment: AppEnvironment.snapshot());
  }

  @override
  bool get isAvailable => _capabilities.supportsAutoUpdate && _feedUrl != null;

  @override
  bool get automaticSilentUpdatesEnabled => _silentCoordinator.automaticSilentUpdatesEnabled;

  @override
  bool get updateNotificationsEnabled => _preferences?.updateNotificationsEnabled ?? true;

  @override
  bool get isSilentCheckInProgress => _silentCoordinator.isSilentCheckInProgress;

  @override
  Future<bool> get hasPendingDownloadedUpdate => _silentCoordinator.hasPendingDownloadedUpdate;

  @override
  bool get hasUpdateAwaitingUserConsent {
    final diagnostics = _silentCoordinator.lastAutomaticDiagnostics;
    if (diagnostics == null) return false;
    if (diagnostics.updateAvailable != true) return false;
    return diagnostics.completionSource == UpdateCheckCompletionSource.automaticAwaitingUserConsent;
  }

  @override
  Stream<void> get changes => _changesController.stream;

  @override
  UpdateCheckDiagnostics? get lastManualDiagnostics => _manualCheckService.lastManualDiagnostics;

  @override
  UpdateCheckDiagnostics? get lastBackgroundDiagnostics => _backgroundCheckService.lastBackgroundDiagnostics;

  @override
  UpdateCheckDiagnostics? get lastAutomaticDiagnostics => _silentCoordinator.lastAutomaticDiagnostics;

  @override
  Future<void> initialize() async {
    final feedUrl = _feedUrl;
    if (feedUrl == null) {
      developer.log(
        'Auto-update skipped: configured feed override is not a Sparkle feed (.xml)',
        name: 'auto_update_orchestrator',
        level: 800,
      );
      return;
    }
    if (_isInitialized) {
      developer.log(
        'Auto-update already initialized, skipping',
        name: 'auto_update_orchestrator',
        level: 800,
      );
      return;
    }
    final updaterIntervalSeconds = _resolveWinSparkleIntervalSeconds();
    try {
      _updaterEventsSubscription ??= _updaterGateway.events.listen(_handleUpdaterEvent);
      await _updaterGateway.setFeedURL(feedUrl);
      await _updaterGateway.setScheduledCheckInterval(updaterIntervalSeconds);
      _isInitialized = true;
      developer.log(
        'Auto-update initialized (feed: $feedUrl, interval: ${updaterIntervalSeconds}s)',
        name: 'auto_update_orchestrator',
        level: 800,
      );
    } on Exception catch (e, s) {
      developer.log(
        'Failed to initialize auto-update',
        name: 'auto_update_orchestrator',
        level: 900,
        error: e,
        stackTrace: s,
      );
    }
  }

  @override
  Future<Result<void>> setAutomaticSilentUpdatesEnabled(bool enabled) async {
    final preferences = _preferences;
    if (preferences == null) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Settings store is not available',
          context: <String, dynamic>{'operation': 'setAutomaticSilentUpdatesEnabled'},
        ),
      );
    }
    try {
      await preferences.setAutomaticSilentUpdatesEnabled(enabled);
      if (_isInitialized) {
        await _updaterGateway.setScheduledCheckInterval(_resolveWinSparkleIntervalSeconds());
      }
      if (!enabled) {
        _silentCoordinator.requestCancellation();
        _silentCoordinator.stop();
        _metricsCollector?.recordAutoUpdateAutomaticSilentPreferenceDisabled();
        await _clearAutomaticDiagnosticsIfFullyManual();
      } else {
        _silentCoordinator.scheduleAndStart();
        _metricsCollector?.recordAutoUpdateAutomaticSilentPreferenceEnabled();
      }
      _notifyChanges();
      return const Success(unit);
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Failed to update automatic silent update preference',
          cause: error,
          context: <String, dynamic>{
            'operation': 'setAutomaticSilentUpdatesEnabled',
            'enabled': enabled,
          },
        ),
      );
    }
  }

  @override
  Future<Result<void>> setUpdateNotificationsEnabled(bool enabled) async {
    final preferences = _preferences;
    if (preferences == null) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Settings store is not available',
          context: <String, dynamic>{'operation': 'setUpdateNotificationsEnabled'},
        ),
      );
    }
    try {
      await preferences.setUpdateNotificationsEnabled(enabled);
      if (_isInitialized) {
        await _updaterGateway.setScheduledCheckInterval(_resolveWinSparkleIntervalSeconds());
      }
      if (enabled) {
        _metricsCollector?.recordAutoUpdateNotificationsPreferenceEnabled();
      } else {
        _metricsCollector?.recordAutoUpdateNotificationsPreferenceDisabled();
        await _clearAutomaticDiagnosticsIfFullyManual();
      }
      _notifyChanges();
      return const Success(unit);
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Failed to update update notification preference',
          cause: error,
          context: <String, dynamic>{
            'operation': 'setUpdateNotificationsEnabled',
            'enabled': enabled,
          },
        ),
      );
    }
  }

  @override
  Future<Result<void>> applyManualOnlyUpdateMode() async {
    final notificationsResult = await setUpdateNotificationsEnabled(false);
    if (notificationsResult.isError()) {
      return notificationsResult;
    }
    final automaticResult = await setAutomaticSilentUpdatesEnabled(false);
    if (automaticResult.isError()) {
      return automaticResult;
    }
    await _clearAutomaticDiagnosticsIfFullyManual();
    _metricsCollector?.recordAutoUpdateManualOnlyModeApplied();
    return const Success(unit);
  }

  Future<void> _clearAutomaticDiagnosticsIfFullyManual() async {
    if (updateNotificationsEnabled || automaticSilentUpdatesEnabled) {
      return;
    }
    await _silentCoordinator.clearPersistedAutomaticDiagnostics();
  }

  @override
  Future<void> startAutomaticChecks() async {
    if (!isAvailable) return;
    await initialize();
    await _silentCoordinator.reconcilePendingAndSchedule();
    if (!automaticSilentUpdatesEnabled && updateNotificationsEnabled) {
      unawaited(checkInBackground());
    }
  }

  @override
  Future<Result<SilentUpdateOutcome>> checkSilently() => _silentCoordinator.checkSilently();

  @override
  Future<Result<void>> applyPendingSilentUpdate({
    String? noticeTitle,
    String? noticeBody,
    bool triggerAppClose = true,
  }) async {
    final result = await _silentCoordinator.applyPendingDownloadedUpdate(
      noticeTitle: noticeTitle,
      noticeBody: noticeBody,
      triggerAppClose: triggerAppClose,
    );
    _notifyChanges();
    return result;
  }

  @override
  Future<Result<void>> applyAvailableUpdate({
    String? noticeTitle,
    String? noticeBody,
  }) async {
    final shouldResumeTimer = automaticSilentUpdatesEnabled;
    if (shouldResumeTimer) {
      _silentCoordinator.stop();
    }
    try {
      final downloadResult = await _silentCoordinator.checkSilently(userInitiated: true);
      SilentUpdateOutcome? outcome;
      Exception? downloadError;
      downloadResult.fold(
        (value) => outcome = value,
        (error) => downloadError = error,
      );
      if (downloadError != null) {
        _metricsCollector?.recordAutoUpdateUserInitiatedApplyFailure();
        _notifyChanges();
        return Failure(downloadError!);
      }
      if (outcome != SilentUpdateOutcome.installerReady) {
        _metricsCollector?.recordAutoUpdateUserInitiatedApplyFailure();
        _notifyChanges();
        return Failure(UserInitiatedApplyFailure.fromOutcome(outcome));
      }
      final applyResult = await _silentCoordinator.applyPendingDownloadedUpdate(
        noticeTitle: noticeTitle,
        noticeBody: noticeBody,
      );
      applyResult.fold(
        (_) => _metricsCollector?.recordAutoUpdateUserInitiatedApplySuccess(),
        (_) => _metricsCollector?.recordAutoUpdateUserInitiatedApplyFailure(),
      );
      _notifyChanges();
      return applyResult;
    } finally {
      if (shouldResumeTimer) {
        _silentCoordinator.scheduleAndStart(runImmediately: false);
      }
    }
  }

  @override
  Future<void> checkInBackground() async {
    if (!isAvailable) return;
    if (automaticSilentUpdatesEnabled) {
      await _silentCoordinator.checkSilently();
      return;
    }
    await _backgroundCheckService.checkInBackground(
      isAvailable: isAvailable,
      automaticSilentUpdatesEnabled: automaticSilentUpdatesEnabled,
      feedUrl: _feedUrl,
    );
  }

  @override
  Future<Result<ManualCheckOutcome>> checkManual() {
    return _manualCheckService.checkManual(
      feedUrl: _feedUrl,
      isInitialized: () => _isInitialized,
      ensureInitialized: initialize,
    );
  }

  void _handleUpdaterEvent(UpdaterEvent event) {
    switch (event) {
      case UpdaterErrorEvent():
        if (_manualCheckService.isManualCheckInProgress) {
          _manualCheckService.onUpdaterError(event.message);
        } else {
          _backgroundCheckService.onUpdaterError(event.message);
        }
      case UpdaterCheckingForUpdate():
        if (_manualCheckService.isManualCheckInProgress) {
          _manualCheckService.onUpdaterCheckingForUpdate(event.itemCount);
        } else {
          _backgroundCheckService.onUpdaterCheckingForUpdate(event.itemCount);
        }
      case UpdaterUpdateAvailable():
        if (_manualCheckService.isManualCheckInProgress) {
          _manualCheckService.onUpdaterUpdateAvailable(
            version: event.version,
            displayVersion: event.displayVersion,
          );
        } else {
          _backgroundCheckService.onUpdaterUpdateAvailable(
            version: event.version,
            displayVersion: event.displayVersion,
          );
        }
      case UpdaterUpdateNotAvailable():
        if (_manualCheckService.isManualCheckInProgress) {
          _manualCheckService.onUpdaterUpdateNotAvailable(errorMessage: event.errorMessage);
        } else {
          _backgroundCheckService.onUpdaterUpdateNotAvailable(errorMessage: event.errorMessage);
        }
      case UpdaterUpdateDownloaded():
        developer.log(
          'Update downloaded: ${event.version}',
          name: 'auto_update_orchestrator',
          level: 800,
        );
      case UpdaterBeforeQuitForUpdate():
        _onUpdaterBeforeQuitForUpdate(event.version);
    }
  }

  void _onUpdaterBeforeQuitForUpdate(String? version) {
    developer.log(
      'Before quit for update: $version',
      name: 'auto_update_orchestrator',
      level: 800,
    );
    final allowQuitForUpdate = _allowQuitForUpdate;
    if (allowQuitForUpdate == null) return;
    try {
      unawaited(
        allowQuitForUpdate().catchError((Object error, StackTrace stackTrace) {
          developer.log(
            'Failed to allow quit for update',
            name: 'auto_update_orchestrator',
            level: 900,
            error: error,
            stackTrace: stackTrace,
          );
        }),
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to allow quit for update',
        name: 'auto_update_orchestrator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
