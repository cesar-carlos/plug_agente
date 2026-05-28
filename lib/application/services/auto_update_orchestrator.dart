import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:auto_updater/auto_updater.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/silent_update_coordinator.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/core/services/update_check_id_recorder.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_auto_update_metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

abstract interface class IAutoUpdaterGateway {
  void addListener(UpdaterListener listener);
  Future<void> setFeedURL(String feedUrl);
  Future<void> checkForUpdates({required bool inBackground});
  Future<void> setScheduledCheckInterval(int interval);
}

class AutoUpdaterGateway implements IAutoUpdaterGateway {
  const AutoUpdaterGateway();

  @override
  void addListener(UpdaterListener listener) {
    autoUpdater.addListener(listener);
  }

  @override
  Future<void> setFeedURL(String feedUrl) {
    return autoUpdater.setFeedURL(feedUrl);
  }

  @override
  Future<void> checkForUpdates({required bool inBackground}) {
    return autoUpdater.checkForUpdates(inBackground: inBackground);
  }

  @override
  Future<void> setScheduledCheckInterval(int interval) {
    return autoUpdater.setScheduledCheckInterval(interval);
  }
}

/// Orchestrates WinSparkle (manual/background) and the silent update path.
///
/// The silent update cycle (probe → download → helper) is fully delegated to
/// [SilentUpdateCoordinator]. This class owns the WinSparkle listener callbacks,
/// the manual check flow, the circuit-breaker for timeouts, and the overall
/// lifecycle (initialize, startAutomaticChecks, setAutomaticSilentUpdatesEnabled).
class AutoUpdateOrchestrator with UpdaterListener implements IAutoUpdateOrchestrator {
  AutoUpdateOrchestrator(
    this._capabilities, {
    IAutoUpdaterGateway updaterGateway = const AutoUpdaterGateway(),
    IAppcastProbeService appcastProbeService = const AppcastProbeService(),
    ISilentUpdateInstaller? silentUpdateInstaller,
    IAppSettingsStore? settingsStore,
    IAutoUpdateMetricsCollector? metricsCollector,
    Future<void> Function()? closeApplicationForSilentUpdate,
    Future<void> Function()? allowQuitForUpdate,
    Duration manualTriggerTimeout = _defaultManualTriggerTimeout,
    Duration manualCompletionTimeout = _defaultManualCompletionTimeout,
    int timeoutCircuitThreshold = _defaultTimeoutCircuitThreshold,
    Duration timeoutCircuitCooldown = _defaultTimeoutCircuitCooldown,
    int backgroundRetryLimit = _defaultBackgroundRetryLimit,
    Duration backgroundRetryBaseDelay = _defaultBackgroundRetryBaseDelay,
    int automaticFailureCooldownThreshold = SilentUpdateCoordinator.defaultAutomaticFailureCooldownThreshold,
    Duration automaticFailureCooldown = SilentUpdateCoordinator.defaultAutomaticFailureCooldown,
    Duration helperWaitDuration = SilentUpdateCoordinator.defaultHelperWaitDuration,
    Duration Function()? automaticBootJitterProvider,
    Duration lateCallbackDrainWindow = _defaultLateCallbackDrainWindow,
    UpdateCheckIdRecorder? checkIdRecorder,
    ISilentUpdateCoordinator? silentUpdateCoordinator,
    Duration backgroundTriggerTimeout = _defaultBackgroundTriggerTimeout,
    double backgroundRetryJitterFactor = _defaultBackgroundRetryJitterFactor,
    Random? random,
  }) : assert(
         backgroundRetryJitterFactor >= 0 && backgroundRetryJitterFactor <= 1,
         'backgroundRetryJitterFactor must be in [0, 1]',
       ),
       _updaterGateway = updaterGateway,
       _appcastProbeService = appcastProbeService,
       _settingsStore = settingsStore,
       _metricsCollector = metricsCollector,
       _allowQuitForUpdate = allowQuitForUpdate,
       _manualTriggerTimeout = manualTriggerTimeout,
       _manualCompletionTimeout = manualCompletionTimeout,
       _timeoutCircuitThreshold = timeoutCircuitThreshold,
       _timeoutCircuitCooldown = timeoutCircuitCooldown,
       _backgroundRetryLimit = backgroundRetryLimit,
       _backgroundRetryBaseDelay = backgroundRetryBaseDelay,
       _backgroundTriggerTimeout = backgroundTriggerTimeout,
       _backgroundRetryJitterFactor = backgroundRetryJitterFactor,
       _random = random ?? Random(),
       _lateCallbackDrainWindow = lateCallbackDrainWindow,
       _checkIdRecorder = checkIdRecorder ?? UpdateCheckIdRecorder(settingsStore: settingsStore) {
    // The coordinator needs a resolver for the feed URL. Using a closure here
    // (after `this` is available) avoids the initializer-list self-reference issue.
    _silentCoordinator =
        silentUpdateCoordinator ??
        SilentUpdateCoordinator(
          _capabilities,
          () => _feedUrl,
          appcastProbeService: appcastProbeService,
          silentUpdateInstaller: silentUpdateInstaller,
          settingsStore: settingsStore,
          closeApplicationForSilentUpdate: closeApplicationForSilentUpdate,
          automaticFailureCooldownThreshold: automaticFailureCooldownThreshold,
          automaticFailureCooldown: automaticFailureCooldown,
          helperWaitDuration: helperWaitDuration,
          bootJitterProvider: automaticBootJitterProvider,
          metricsCollector: metricsCollector,
          checkIdRecorder: _checkIdRecorder,
        );
    _hydratePersistedDiagnostics();
  }

  final RuntimeCapabilities _capabilities;
  final IAutoUpdaterGateway _updaterGateway;
  final IAppcastProbeService _appcastProbeService;
  final IAppSettingsStore? _settingsStore;
  final IAutoUpdateMetricsCollector? _metricsCollector;
  final Future<void> Function()? _allowQuitForUpdate;
  final Duration _manualTriggerTimeout;
  final Duration _manualCompletionTimeout;
  final int _timeoutCircuitThreshold;
  final Duration _timeoutCircuitCooldown;
  final int _backgroundRetryLimit;
  final Duration _backgroundRetryBaseDelay;
  final Duration _backgroundTriggerTimeout;
  final double _backgroundRetryJitterFactor;
  final Random _random;
  final Duration _lateCallbackDrainWindow;
  final UpdateCheckIdRecorder _checkIdRecorder;
  late final ISilentUpdateCoordinator _silentCoordinator;

  bool _isInitialized = false;
  Completer<Result<ManualCheckOutcome>>? _manualCheckCompleter;
  bool _isManualCheck = false;
  bool _isBackgroundCheckInProgress = false;
  UpdateCheckDiagnostics? _activeManualDiagnostics;
  UpdateCheckDiagnostics? _lastManualDiagnostics;
  UpdateCheckDiagnostics? _lastBackgroundDiagnostics;
  String? _activeCheckId;
  DateTime? _lastManualCheckEndedAt;

  static const String _lastDiagnosticsKey = 'auto_update.last_manual_diagnostics';
  static const String _lastBackgroundDiagnosticsKey = 'auto_update.last_background_diagnostics';
  static const String _timeoutConsecutiveCountKey = 'auto_update.timeout_consecutive_count';
  static const String _timeoutCooldownUntilKey = 'auto_update.timeout_cooldown_until_ms';

  static const int _defaultTimeoutCircuitThreshold = 3;
  static const Duration _defaultTimeoutCircuitCooldown = Duration(minutes: 15);
  static const int _defaultBackgroundRetryLimit = 3;
  static const Duration _defaultBackgroundRetryBaseDelay = Duration(seconds: 30);
  static const Duration _defaultManualTriggerTimeout = Duration(seconds: 15);
  static const Duration _defaultManualCompletionTimeout = Duration(seconds: 60);

  /// Default timeout for the background `checkForUpdates` trigger. Mirrors
  /// [_defaultManualTriggerTimeout] doubled — background has no user waiting,
  /// so we tolerate a slightly longer trigger before retrying. Without this
  /// timeout an unresponsive updater process could leave the background retry
  /// loop blocked indefinitely.
  static const Duration _defaultBackgroundTriggerTimeout = Duration(seconds: 30);

  /// Default ±jitter applied to the background retry backoff. Avoids
  /// synchronizing retries across fleets of agents started together when the
  /// update server is degraded.
  static const double _defaultBackgroundRetryJitterFactor = 0.2;

  /// Window during which WinSparkle callbacks arriving without `_isManualCheck`
  /// are treated as late echoes of a manual check that already timed out
  /// instead of polluting background diagnostics.
  static const Duration _defaultLateCallbackDrainWindow = Duration(seconds: 30);

  String? get _feedUrl {
    final url = resolveAutoUpdateFeedUrl(environment: AppEnvironment.snapshot());
    if (url.isEmpty) return null;
    return isSparkleFeedUrl(url) ? url : null;
  }

  String _buildManualFeedUrl(String baseFeedUrl) {
    final uri = Uri.tryParse(baseFeedUrl);
    if (uri == null) return baseFeedUrl;
    final query = Map<String, String>.from(uri.queryParameters);
    query['cb'] = DateTime.now().millisecondsSinceEpoch.toString();
    return uri.replace(queryParameters: query).toString();
  }

  String _extractFailureMessage(Exception error) {
    if (error is domain.Failure) return error.message;
    return error.toString();
  }

  void _logManualCheck(
    String message, {
    int level = 800,
    String? checkId,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final diagnostics = _activeManualDiagnostics;
    final context = <String>[
      if (checkId != null) 'check_id=$checkId',
      if (diagnostics != null) 'configured_feed=${diagnostics.configuredFeedUrl}',
      if (diagnostics?.probeRequestUrl != null) 'probe_request_url=${diagnostics!.probeRequestUrl}',
      if (diagnostics?.completionSource != null) 'completion_source=${diagnostics!.completionSource!.name}',
    ].join(' | ');
    developer.log(
      context.isEmpty ? message : '$message | $context',
      name: 'auto_update_orchestrator',
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }

  domain.Failure _buildManualFailure({
    required String message,
    required UpdateCheckCompletionSource completionSource,
    Exception? cause,
    Map<String, dynamic> context = const <String, dynamic>{},
  }) {
    return domain.ServerFailure.withContext(
      message: message,
      cause: cause,
      context: <String, dynamic>{
        'operation': 'checkManual',
        'completion_source': completionSource.name,
        if (_activeCheckId != null) 'check_id': _activeCheckId,
        ...context,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // IAutoUpdateOrchestrator — getters
  // ---------------------------------------------------------------------------

  @override
  bool get isAvailable => _capabilities.supportsAutoUpdate && _feedUrl != null;

  @override
  bool get automaticSilentUpdatesEnabled => _silentCoordinator.automaticSilentUpdatesEnabled;

  @override
  bool get isSilentCheckInProgress => _silentCoordinator.isSilentCheckInProgress;

  @override
  UpdateCheckDiagnostics? get lastManualDiagnostics => _lastManualDiagnostics;

  @override
  UpdateCheckDiagnostics? get lastBackgroundDiagnostics => _lastBackgroundDiagnostics;

  @override
  UpdateCheckDiagnostics? get lastAutomaticDiagnostics => _silentCoordinator.lastAutomaticDiagnostics;

  // ---------------------------------------------------------------------------
  // Diagnostics persistence (manual / background — Sparkle path)
  // ---------------------------------------------------------------------------

  void _hydratePersistedDiagnostics() {
    final raw = _settingsStore?.getString(_lastDiagnosticsKey);
    if (raw == null || raw.isEmpty) {
      _hydratePersistedBackgroundDiagnostics();
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _lastManualDiagnostics = UpdateCheckDiagnostics.fromJson(decoded);
      }
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Failed to parse persisted auto-update diagnostics',
        name: 'auto_update_orchestrator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
    _hydratePersistedBackgroundDiagnostics();
  }

  void _hydratePersistedBackgroundDiagnostics() {
    final raw = _settingsStore?.getString(_lastBackgroundDiagnosticsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _lastBackgroundDiagnostics = UpdateCheckDiagnostics.fromJson(decoded);
      }
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Failed to parse persisted background auto-update diagnostics',
        name: 'auto_update_orchestrator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _persistLastManualDiagnostics() async {
    final settingsStore = _settingsStore;
    final diagnostics = _lastManualDiagnostics;
    if (settingsStore == null || diagnostics == null) return;
    try {
      await settingsStore.setString(
        _lastDiagnosticsKey,
        jsonEncode(diagnostics.toJson()),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to persist auto-update diagnostics',
        name: 'auto_update_orchestrator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _persistLastBackgroundDiagnostics() async {
    final settingsStore = _settingsStore;
    final diagnostics = _lastBackgroundDiagnostics;
    if (settingsStore == null || diagnostics == null) return;
    try {
      await settingsStore.setString(
        _lastBackgroundDiagnosticsKey,
        jsonEncode(diagnostics.toJson()),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to persist background auto-update diagnostics',
        name: 'auto_update_orchestrator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Timeout circuit breaker (manual check)
  // ---------------------------------------------------------------------------

  int _consecutiveTimeoutCount() => _settingsStore?.getInt(_timeoutConsecutiveCountKey) ?? 0;

  DateTime? _timeoutCooldownUntil() {
    final timestamp = _settingsStore?.getInt(_timeoutCooldownUntilKey);
    if (timestamp == null || timestamp <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Future<void> _recordTimeoutOutcome() async {
    final settingsStore = _settingsStore;
    if (settingsStore == null) return;
    final nextCount = _consecutiveTimeoutCount() + 1;
    final values = <String, Object>{_timeoutConsecutiveCountKey: nextCount};
    if (nextCount >= _timeoutCircuitThreshold) {
      final cooldownUntil = DateTime.now().add(_timeoutCircuitCooldown);
      values[_timeoutCooldownUntilKey] = cooldownUntil.millisecondsSinceEpoch;
      _metricsCollector?.recordAutoUpdateCircuitOpened();
      _logManualCheck('Auto-update manual check circuit opened', checkId: _activeCheckId, level: 900);
    }
    try {
      await settingsStore.setValues(values);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to persist auto-update timeout state',
        name: 'auto_update_orchestrator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _resetTimeoutCircuitIfNeeded() async {
    final settingsStore = _settingsStore;
    if (settingsStore == null) return;
    final hasTimeoutCount = settingsStore.containsKey(_timeoutConsecutiveCountKey);
    final hasCooldown = settingsStore.containsKey(_timeoutCooldownUntilKey);
    if (!hasTimeoutCount && !hasCooldown) return;
    try {
      await settingsStore.remove(_timeoutConsecutiveCountKey);
      await settingsStore.remove(_timeoutCooldownUntilKey);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to reset auto-update timeout circuit state',
        name: 'auto_update_orchestrator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<Result<ManualCheckOutcome>?> _buildCircuitOpenFailure(String feedUrl) async {
    final cooldownUntil = _timeoutCooldownUntil();
    if (cooldownUntil == null) return null;
    final remaining = cooldownUntil.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      await _resetTimeoutCircuitIfNeeded();
      return null;
    }
    final minutesRemaining = remaining.inMinutes;
    final humanRemaining = minutesRemaining >= 1 ? '$minutesRemaining min' : '${remaining.inSeconds}s';
    final now = DateTime.now();
    final failure = Failure<ManualCheckOutcome, Exception>(
      _buildManualFailure(
        message:
            'Update checks are temporarily paused after repeated updater timeouts. '
            'Try again in about $humanRemaining.',
        completionSource: UpdateCheckCompletionSource.circuitOpen,
        context: <String, dynamic>{'cooldown_remaining_ms': remaining.inMilliseconds},
      ),
    );
    _lastManualDiagnostics = UpdateCheckDiagnostics(
      checkedAt: now,
      configuredFeedUrl: feedUrl,
      requestedFeedUrl: feedUrl,
      currentVersion: AppConstants.appVersion,
      completedAt: now,
      completionSource: UpdateCheckCompletionSource.circuitOpen,
      errorMessage:
          'Update checks are temporarily paused after repeated updater timeouts. '
          'Try again in about $humanRemaining.',
    );
    await _persistLastManualDiagnostics();
    _metricsCollector?.recordAutoUpdateCircuitOpenRejected();
    return failure;
  }

  // ---------------------------------------------------------------------------
  // Metrics / diagnostics helpers
  // ---------------------------------------------------------------------------

  void _recordCompletionMetric(UpdateCheckCompletionSource source) {
    final metricsCollector = _metricsCollector;
    if (metricsCollector == null) return;
    switch (source) {
      case UpdateCheckCompletionSource.updateAvailable:
        metricsCollector.recordAutoUpdateManualCheckSuccessAvailable();
      case UpdateCheckCompletionSource.updateNotAvailable:
        metricsCollector.recordAutoUpdateManualCheckSuccessNotAvailable();
      case UpdateCheckCompletionSource.updaterError:
        metricsCollector.recordAutoUpdateManualCheckUpdaterError();
      case UpdateCheckCompletionSource.triggerTimeout:
        metricsCollector.recordAutoUpdateManualCheckTriggerTimeout();
      case UpdateCheckCompletionSource.completionTimeout:
        metricsCollector.recordAutoUpdateManualCheckCompletionTimeout();
      case UpdateCheckCompletionSource.triggerFailure:
        metricsCollector.recordAutoUpdateManualCheckTriggerFailure();
      case UpdateCheckCompletionSource.notInitialized:
        metricsCollector.recordAutoUpdateManualCheckNotInitialized();
      case UpdateCheckCompletionSource.circuitOpen:
        metricsCollector.recordAutoUpdateCircuitOpenRejected();
      case UpdateCheckCompletionSource.automaticDisabled:
      case UpdateCheckCompletionSource.automaticPendingCompleted:
      case UpdateCheckCompletionSource.automaticPendingFailed:
      case UpdateCheckCompletionSource.automaticUpdateNotAvailable:
      case UpdateCheckCompletionSource.automaticValidationFailure:
      case UpdateCheckCompletionSource.automaticDownloadFailure:
      case UpdateCheckCompletionSource.automaticInstallStarted:
      case UpdateCheckCompletionSource.automaticInstallFailure:
      case UpdateCheckCompletionSource.automaticCooldown:
      case UpdateCheckCompletionSource.automaticRolloutSkipped:
      case UpdateCheckCompletionSource.automaticCancelled:
      case UpdateCheckCompletionSource.automaticQuietHours:
        break;
    }
  }

  UpdateCheckDiagnostics _buildBackgroundDiagnostics(String feedUrl) {
    final now = DateTime.now();
    final id = _checkIdRecorder.newId();
    unawaited(_checkIdRecorder.record(id, source: 'background'));
    return UpdateCheckDiagnostics(
      checkedAt: now,
      configuredFeedUrl: feedUrl,
      requestedFeedUrl: feedUrl,
      checkId: id,
      currentVersion: AppConstants.appVersion,
      triggerStartedAt: now,
    );
  }

  UpdateCheckDiagnostics _backgroundDiagnosticsOrDefault() {
    final feedUrl = _feedUrl ?? officialAutoUpdateFeedUrl;
    return _lastBackgroundDiagnostics ??
        UpdateCheckDiagnostics(
          checkedAt: DateTime.now(),
          configuredFeedUrl: feedUrl,
          requestedFeedUrl: feedUrl,
          currentVersion: AppConstants.appVersion,
        );
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

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
    final intervalSeconds = resolveAutoUpdateCheckIntervalSeconds(
      environment: AppEnvironment.snapshot(),
    );
    final updaterIntervalSeconds = automaticSilentUpdatesEnabled ? 0 : intervalSeconds;
    try {
      _updaterGateway.addListener(this);
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
    final settingsStore = _settingsStore;
    if (settingsStore == null) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Settings store is not available',
          context: <String, dynamic>{'operation': 'setAutomaticSilentUpdatesEnabled'},
        ),
      );
    }
    try {
      await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, enabled);
      if (_isInitialized) {
        final intervalSeconds = enabled
            ? 0
            : resolveAutoUpdateCheckIntervalSeconds(environment: AppEnvironment.snapshot());
        await _updaterGateway.setScheduledCheckInterval(intervalSeconds);
      }
      if (!enabled) {
        // Signal in-flight check (if any) to bail out at the next safe
        // checkpoint before tearing down the periodic timer; cancellation is
        // a no-op when no check is running.
        _silentCoordinator.requestCancellation();
        _silentCoordinator.stop();
      } else {
        _silentCoordinator.scheduleAndStart();
      }
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
  Future<void> startAutomaticChecks() async {
    if (!isAvailable) return;
    await initialize();
    await _silentCoordinator.reconcilePendingAndSchedule();
    if (!automaticSilentUpdatesEnabled) {
      unawaited(checkInBackground());
    }
  }

  // ---------------------------------------------------------------------------
  // Update checks
  // ---------------------------------------------------------------------------

  @override
  Future<Result<SilentUpdateOutcome>> checkSilently() => _silentCoordinator.checkSilently();

  @override
  Future<void> checkInBackground() async {
    if (!isAvailable) return;
    if (automaticSilentUpdatesEnabled) {
      await _silentCoordinator.checkSilently();
      return;
    }
    if (_isBackgroundCheckInProgress) {
      developer.log(
        'Background update check skipped: another background check is already running',
        name: 'auto_update_orchestrator',
        level: 800,
      );
      return;
    }
    final feedUrl = _feedUrl;
    if (feedUrl == null) return;
    _isBackgroundCheckInProgress = true;
    try {
      for (var attempt = 1; attempt <= _backgroundRetryLimit; attempt++) {
        _lastBackgroundDiagnostics = _buildBackgroundDiagnostics(feedUrl);
        try {
          // Bounded trigger: without a timeout an unresponsive updater process
          // would leave the await suspended indefinitely, blocking the retry
          // loop and any future cycles (until the app restarts).
          await _updaterGateway
              .checkForUpdates(inBackground: true)
              .timeout(_backgroundTriggerTimeout);
          _lastBackgroundDiagnostics = _lastBackgroundDiagnostics?.copyWith(
            triggerCompletedAt: DateTime.now(),
          );
          unawaited(_persistLastBackgroundDiagnostics());
          return;
        } on Exception catch (e, s) {
          final completedAt = DateTime.now();
          _lastBackgroundDiagnostics = _lastBackgroundDiagnostics?.copyWith(
            triggerCompletedAt: completedAt,
            completedAt: completedAt,
            completionSource: UpdateCheckCompletionSource.triggerFailure,
            errorMessage: e.toString(),
          );
          _metricsCollector?.recordAutoUpdateBackgroundCheckTriggerFailure();
          unawaited(_persistLastBackgroundDiagnostics());
          developer.log(
            'Background update check failed (attempt $attempt/$_backgroundRetryLimit)',
            name: 'auto_update_orchestrator',
            level: 900,
            error: e,
            stackTrace: s,
          );
          if (attempt < _backgroundRetryLimit) {
            final delay = _jitteredBackgroundRetryDelay(attempt);
            developer.log(
              'Retrying in ${delay.inMilliseconds}ms',
              name: 'auto_update_orchestrator',
              level: 800,
            );
            await Future<void>.delayed(delay);
          }
        }
      }
    } finally {
      _isBackgroundCheckInProgress = false;
    }
  }

  /// Computes the delay before the next background retry attempt, applying
  /// ±[_backgroundRetryJitterFactor] perturbation on top of the linear base.
  /// Returns at least 100ms so the event loop always yields.
  Duration _jitteredBackgroundRetryDelay(int attempt) {
    final baseMs = (_backgroundRetryBaseDelay * attempt).inMilliseconds;
    if (_backgroundRetryJitterFactor == 0 || baseMs <= 0) {
      return Duration(milliseconds: baseMs);
    }
    final span = baseMs * _backgroundRetryJitterFactor;
    final offset = (_random.nextDouble() * 2 - 1) * span;
    final jitteredMs = (baseMs + offset).round();
    return Duration(milliseconds: jitteredMs < 100 ? 100 : jitteredMs);
  }

  @override
  Future<Result<ManualCheckOutcome>> checkManual() async {
    if (!_capabilities.supportsAutoUpdate) {
      return Failure<ManualCheckOutcome, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Auto-update is not supported in current runtime mode',
          context: {'operation': 'checkManual'},
        ),
      );
    }
    final feedUrl = _feedUrl;
    if (feedUrl == null) {
      return Failure<ManualCheckOutcome, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Update feed URL is not configured',
          context: {'operation': 'checkManual'},
        ),
      );
    }
    final circuitOpenFailure = await _buildCircuitOpenFailure(feedUrl);
    if (circuitOpenFailure != null) return circuitOpenFailure;
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized) {
        final failure = Failure<ManualCheckOutcome, Exception>(
          _buildManualFailure(
            message: 'Auto-update is not initialized',
            completionSource: UpdateCheckCompletionSource.notInitialized,
          ),
        );
        _lastManualDiagnostics = UpdateCheckDiagnostics(
          checkedAt: DateTime.now(),
          configuredFeedUrl: feedUrl,
          requestedFeedUrl: feedUrl,
          currentVersion: AppConstants.appVersion,
          completedAt: DateTime.now(),
          completionSource: UpdateCheckCompletionSource.notInitialized,
          errorMessage: 'Auto-update is not initialized',
        );
        await _persistLastManualDiagnostics();
        _recordCompletionMetric(UpdateCheckCompletionSource.notInitialized);
        return failure;
      }
    }
    if (_isManualCheck) {
      return Failure<ManualCheckOutcome, Exception>(
        domain.ServerFailure.withContext(
          message: 'Update check already in progress',
          context: {'operation': 'checkManual'},
        ),
      );
    }
    _manualCheckCompleter = Completer<Result<ManualCheckOutcome>>();
    _isManualCheck = true;
    _activeCheckId = _checkIdRecorder.newId();
    unawaited(_checkIdRecorder.record(_activeCheckId!, source: 'manual'));
    final manualFeedUrl = _buildManualFeedUrl(feedUrl);
    _metricsCollector?.recordAutoUpdateManualCheckStarted();
    _activeManualDiagnostics = UpdateCheckDiagnostics(
      checkedAt: DateTime.now(),
      configuredFeedUrl: feedUrl,
      requestedFeedUrl: manualFeedUrl,
      checkId: _activeCheckId,
      currentVersion: AppConstants.appVersion,
      probeRequestUrl: manualFeedUrl,
    );
    try {
      _logManualCheck('Manual update check triggered', checkId: _activeCheckId);
      final probeResult = await _appcastProbeService.probeLatest(feedUrl: manualFeedUrl);
      _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
        probeRequestUrl: probeResult.requestUrl,
        probeSucceeded: probeResult.errorMessage == null,
        appcastProbeVersion: probeResult.latestVersion,
        appcastProbeOs: probeResult.os,
        appcastProbeItemCount: probeResult.itemCount,
        probeErrorMessage: probeResult.errorMessage,
        releaseNotes: probeResult.releaseNotes,
        releaseNotesUrl: probeResult.releaseNotesUrl,
      );
      final triggerStartedAt = DateTime.now();
      _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
        triggerStartedAt: triggerStartedAt,
      );
      // Use WinSparkle check without UI so the Settings dialog is the only user-facing
      // result for "no update" / errors; native "up to date" duplicates Fluent feedback.
      await _updaterGateway.checkForUpdates(inBackground: true).timeout(_manualTriggerTimeout);
      final triggerCompletedAt = DateTime.now();
      _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
        triggerCompletedAt: triggerCompletedAt,
      );
      _logManualCheck(
        'Manual update trigger returned to Dart '
        '(trigger_duration_ms=${triggerCompletedAt.difference(triggerStartedAt).inMilliseconds})',
        checkId: _activeCheckId,
      );
      return await _manualCheckCompleter!.future.timeout(
        _manualCompletionTimeout,
        onTimeout: () {
          final failure = Failure<ManualCheckOutcome, Exception>(
            _buildManualFailure(
              message: 'Update check timed out while waiting for updater completion',
              completionSource: UpdateCheckCompletionSource.completionTimeout,
            ),
          );
          _completeManualCheck(failure, completionSource: UpdateCheckCompletionSource.completionTimeout);
          return failure;
        },
      );
    } on TimeoutException catch (e) {
      final now = DateTime.now();
      _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(triggerCompletedAt: now);
      final failure = Failure<ManualCheckOutcome, Exception>(
        _buildManualFailure(
          message: 'Update check trigger timed out before updater responded',
          completionSource: UpdateCheckCompletionSource.triggerTimeout,
          cause: e,
        ),
      );
      _completeManualCheck(failure, completionSource: UpdateCheckCompletionSource.triggerTimeout);
      return failure;
    } on Exception catch (e) {
      final failure = Failure<ManualCheckOutcome, Exception>(
        _buildManualFailure(
          message: 'Failed to trigger update check',
          cause: e,
          completionSource: UpdateCheckCompletionSource.triggerFailure,
        ),
      );
      _completeManualCheck(failure, completionSource: UpdateCheckCompletionSource.triggerFailure);
      return failure;
    } finally {
      _lastManualDiagnostics = _activeManualDiagnostics;
      final completionSource = _lastManualDiagnostics?.completionSource;
      if (completionSource == UpdateCheckCompletionSource.triggerTimeout ||
          completionSource == UpdateCheckCompletionSource.completionTimeout) {
        await _recordTimeoutOutcome();
      } else if (completionSource != null && completionSource != UpdateCheckCompletionSource.circuitOpen) {
        await _resetTimeoutCircuitIfNeeded();
      }
      await _persistLastManualDiagnostics();
      _activeManualDiagnostics = null;
      _isManualCheck = false;
      _manualCheckCompleter = null;
      _activeCheckId = null;
      _lastManualCheckEndedAt = DateTime.now();
    }
  }

  /// True when a callback from WinSparkle arrived after `checkManual` already
  /// ended (typically via [_manualCompletionTimeout]) and within
  /// [_lateCallbackDrainWindow]. These callbacks must not be persisted as
  /// background diagnostics or count as background failures.
  bool _isLateManualCallback() {
    final lastEndedAt = _lastManualCheckEndedAt;
    if (lastEndedAt == null) return false;
    return DateTime.now().difference(lastEndedAt) <= _lateCallbackDrainWindow;
  }

  void _completeManualCheck(
    Result<ManualCheckOutcome> result, {
    UpdateCheckCompletionSource? completionSource,
  }) {
    final completedAt = DateTime.now();
    final isTrackedManualCheck = _activeManualDiagnostics != null;
    result.fold(
      (outcome) {
        final resolvedCompletionSource =
            completionSource ??
            (outcome.isUpdateAvailable
                ? UpdateCheckCompletionSource.updateAvailable
                : UpdateCheckCompletionSource.updateNotAvailable);
        _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
          completedAt: completedAt,
          completionSource: resolvedCompletionSource,
          updateAvailable: outcome.isUpdateAvailable,
        );
        if (isTrackedManualCheck) _recordCompletionMetric(resolvedCompletionSource);
      },
      (error) {
        final resolvedCompletionSource = completionSource ?? UpdateCheckCompletionSource.updaterError;
        _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
          completedAt: completedAt,
          completionSource: resolvedCompletionSource,
          errorMessage: _extractFailureMessage(error),
        );
        if (isTrackedManualCheck) _recordCompletionMetric(resolvedCompletionSource);
      },
    );
    final diagnostics = _activeManualDiagnostics;
    if (diagnostics != null && diagnostics.triggerStartedAt != null && diagnostics.triggerCompletedAt != null) {
      final triggerDuration = diagnostics.triggerCompletedAt!.difference(diagnostics.triggerStartedAt!).inMilliseconds;
      final totalDuration = completedAt.difference(diagnostics.checkedAt).inMilliseconds;
      _logManualCheck(
        'Manual update check completed '
        '(trigger_duration_ms=$triggerDuration, total_duration_ms=$totalDuration)',
        checkId: _activeCheckId,
      );
    } else {
      _logManualCheck('Manual update check completed', checkId: _activeCheckId);
    }
    if (_isManualCheck && _manualCheckCompleter != null && !_manualCheckCompleter!.isCompleted) {
      _manualCheckCompleter!.complete(result);
    }
  }

  // ---------------------------------------------------------------------------
  // WinSparkle listener callbacks
  // ---------------------------------------------------------------------------

  @override
  void onUpdaterError(UpdaterError? error) {
    if (!_isManualCheck) {
      if (_isLateManualCallback()) {
        developer.log(
          'Ignoring late auto-updater error from a previously timed-out manual check: $error',
          name: 'auto_update_orchestrator',
          level: 800,
        );
        return;
      }
      _lastBackgroundDiagnostics = _backgroundDiagnosticsOrDefault().copyWith(
        completedAt: DateTime.now(),
        completionSource: UpdateCheckCompletionSource.updaterError,
        errorMessage: error?.toString() ?? 'Update check failed',
      );
      _metricsCollector?.recordAutoUpdateBackgroundCheckUpdaterError();
      unawaited(_persistLastBackgroundDiagnostics());
      developer.log('Background auto-updater error: $error', name: 'auto_update_orchestrator', level: 900);
      return;
    }
    _logManualCheck('Auto-updater error: $error', checkId: _activeCheckId, level: 900);
    _completeManualCheck(
      Failure<ManualCheckOutcome, Exception>(
        _buildManualFailure(
          message: error?.toString() ?? 'Update check failed',
          completionSource: UpdateCheckCompletionSource.updaterError,
          context: {'operation': 'onUpdaterError'},
        ),
      ),
      completionSource: UpdateCheckCompletionSource.updaterError,
    );
  }

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    if (!_isManualCheck) {
      if (_isLateManualCallback()) {
        developer.log(
          'Ignoring late checking-for-update from a previously timed-out manual check',
          name: 'auto_update_orchestrator',
          level: 800,
        );
        return;
      }
      final diagnostics = _backgroundDiagnosticsOrDefault();
      _lastBackgroundDiagnostics = diagnostics.copyWith(
        triggerStartedAt: diagnostics.triggerStartedAt ?? DateTime.now(),
      );
      unawaited(_persistLastBackgroundDiagnostics());
      developer.log(
        'Background check for updates... (items: ${appcast?.items.length ?? 0})',
        name: 'auto_update_orchestrator',
        level: 800,
      );
      return;
    }
    _logManualCheck(
      'Checking for updates... (items: ${appcast?.items.length ?? 0})',
      checkId: _activeCheckId,
    );
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    if (!_isManualCheck) {
      if (_isLateManualCallback()) {
        developer.log(
          'Ignoring late update-available from a previously timed-out manual check: '
          '${appcastItem?.versionString}',
          name: 'auto_update_orchestrator',
          level: 800,
        );
        return;
      }
      _lastBackgroundDiagnostics = _backgroundDiagnosticsOrDefault().copyWith(
        completedAt: DateTime.now(),
        completionSource: UpdateCheckCompletionSource.updateAvailable,
        updateAvailable: true,
        remoteVersion: appcastItem?.versionString,
        remoteDisplayVersion: appcastItem?.displayVersionString,
      );
      unawaited(_persistLastBackgroundDiagnostics());
      developer.log(
        'Background update available: ${appcastItem?.versionString} '
        '(display: ${appcastItem?.displayVersionString})',
        name: 'auto_update_orchestrator',
        level: 800,
      );
      return;
    }
    _logManualCheck(
      'Update available: ${appcastItem?.versionString} '
      '(display: ${appcastItem?.displayVersionString})',
      checkId: _activeCheckId,
    );
    final sparkleVersion = appcastItem?.versionString;
    final probeVersion = _activeManualDiagnostics?.appcastProbeVersion;
    final probeMatchesSparkle = sparkleVersion != null && probeVersion != null ? sparkleVersion == probeVersion : null;
    if (probeMatchesSparkle == false) {
      _logManualCheck(
        'Probe version ($probeVersion) does not match Sparkle version ($sparkleVersion) '
        '— possible CDN cache skew',
        checkId: _activeCheckId,
        level: 900,
      );
    }
    _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
      remoteVersion: sparkleVersion,
      remoteDisplayVersion: appcastItem?.displayVersionString,
      probeMatchesSparkle: probeMatchesSparkle,
    );
    _completeManualCheck(
      const Success(ManualCheckOutcome.updateAvailable),
      completionSource: UpdateCheckCompletionSource.updateAvailable,
    );
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    if (!_isManualCheck) {
      if (_isLateManualCallback()) {
        developer.log(
          'Ignoring late update-not-available from a previously timed-out manual check',
          name: 'auto_update_orchestrator',
          level: 800,
        );
        return;
      }
      _lastBackgroundDiagnostics = _backgroundDiagnosticsOrDefault().copyWith(
        completedAt: DateTime.now(),
        completionSource: UpdateCheckCompletionSource.updateNotAvailable,
        updateAvailable: false,
        errorMessage: error?.message,
      );
      unawaited(_persistLastBackgroundDiagnostics());
      developer.log(
        'No background update available (error: $error)',
        name: 'auto_update_orchestrator',
        level: 800,
      );
      return;
    }
    _logManualCheck(
      'No update available (manual: $_isManualCheck, error: $error)',
      checkId: _activeCheckId,
    );
    // Probe found a version but Sparkle says no update — also a skew signal.
    final probeVersion = _activeManualDiagnostics?.appcastProbeVersion;
    if (probeVersion != null) {
      _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(probeMatchesSparkle: false);
      _logManualCheck(
        'Probe found version ($probeVersion) but Sparkle reports no update '
        '— possible CDN cache skew',
        checkId: _activeCheckId,
        level: 900,
      );
    }
    if (error != null) {
      _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(errorMessage: error.message);
    }
    _completeManualCheck(
      const Success(ManualCheckOutcome.noUpdate),
      completionSource: UpdateCheckCompletionSource.updateNotAvailable,
    );
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    _logManualCheck('Update downloaded: ${appcastItem?.versionString}', checkId: _activeCheckId);
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    _logManualCheck(
      'Before quit for update: ${appcastItem?.versionString}',
      checkId: _activeCheckId,
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
