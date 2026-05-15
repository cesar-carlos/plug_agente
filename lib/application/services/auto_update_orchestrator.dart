import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:auto_updater/auto_updater.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/versioning/app_version_comparator.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';
import 'package:window_manager/window_manager.dart';

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

class AutoUpdateOrchestrator with UpdaterListener implements IAutoUpdateOrchestrator {
  AutoUpdateOrchestrator(
    this._capabilities, {
    IAutoUpdaterGateway updaterGateway = const AutoUpdaterGateway(),
    IAppcastProbeService appcastProbeService = const AppcastProbeService(),
    ISilentUpdateInstaller? silentUpdateInstaller,
    IAppSettingsStore? settingsStore,
    MetricsCollector? metricsCollector,
    Future<void> Function()? closeApplicationForSilentUpdate,
    Duration manualTriggerTimeout = _defaultManualTriggerTimeout,
    Duration manualCompletionTimeout = _defaultManualCompletionTimeout,
    int timeoutCircuitThreshold = _defaultTimeoutCircuitThreshold,
    Duration timeoutCircuitCooldown = _defaultTimeoutCircuitCooldown,
    int backgroundRetryLimit = _defaultBackgroundRetryLimit,
    Duration backgroundRetryBaseDelay = _defaultBackgroundRetryBaseDelay,
    int automaticFailureCooldownThreshold = _defaultAutomaticFailureCooldownThreshold,
    Duration automaticFailureCooldown = _defaultAutomaticFailureCooldown,
  }) : _updaterGateway = updaterGateway,
       _appcastProbeService = appcastProbeService,
       _silentUpdateInstaller = silentUpdateInstaller,
       _settingsStore = settingsStore,
       _metricsCollector = metricsCollector,
       _closeApplicationForSilentUpdate = closeApplicationForSilentUpdate,
       _manualTriggerTimeout = manualTriggerTimeout,
       _manualCompletionTimeout = manualCompletionTimeout,
       _timeoutCircuitThreshold = timeoutCircuitThreshold,
       _timeoutCircuitCooldown = timeoutCircuitCooldown,
       _backgroundRetryLimit = backgroundRetryLimit,
       _backgroundRetryBaseDelay = backgroundRetryBaseDelay,
       _automaticFailureCooldownThreshold = automaticFailureCooldownThreshold,
       _automaticFailureCooldown = automaticFailureCooldown {
    _hydratePersistedDiagnostics();
  }

  final RuntimeCapabilities _capabilities;
  final IAutoUpdaterGateway _updaterGateway;
  final IAppcastProbeService _appcastProbeService;
  final ISilentUpdateInstaller? _silentUpdateInstaller;
  final IAppSettingsStore? _settingsStore;
  final MetricsCollector? _metricsCollector;
  final Future<void> Function()? _closeApplicationForSilentUpdate;
  final Duration _manualTriggerTimeout;
  final Duration _manualCompletionTimeout;
  final int _timeoutCircuitThreshold;
  final Duration _timeoutCircuitCooldown;
  final int _backgroundRetryLimit;
  final Duration _backgroundRetryBaseDelay;
  final int _automaticFailureCooldownThreshold;
  final Duration _automaticFailureCooldown;

  bool _isInitialized = false;
  Completer<Result<bool>>? _manualCheckCompleter;
  bool _isManualCheck = false;
  UpdateCheckDiagnostics? _activeManualDiagnostics;
  UpdateCheckDiagnostics? _lastManualDiagnostics;
  UpdateCheckDiagnostics? _lastBackgroundDiagnostics;
  UpdateCheckDiagnostics? _lastAutomaticDiagnostics;
  String? _activeCheckId;
  Timer? _automaticCheckTimer;
  bool _isSilentCheckInProgress = false;

  static const String _lastDiagnosticsKey = 'auto_update.last_manual_diagnostics';
  static const String _lastBackgroundDiagnosticsKey = 'auto_update.last_background_diagnostics';
  static const String _lastAutomaticDiagnosticsKey = 'auto_update.last_automatic_diagnostics';
  static const String _pendingSilentUpdateKey = 'auto_update.pending_silent_update';
  static const String _automaticFailureCountKey = 'auto_update.automatic_failure_count';
  static const String _automaticCooldownUntilKey = 'auto_update.automatic_cooldown_until_ms';
  static const String _automaticRolloutBucketKey = 'auto_update.rollout_bucket';
  static const String _timeoutConsecutiveCountKey = 'auto_update.timeout_consecutive_count';
  static const String _timeoutCooldownUntilKey = 'auto_update.timeout_cooldown_until_ms';
  static const int _defaultTimeoutCircuitThreshold = 3;
  static const Duration _defaultTimeoutCircuitCooldown = Duration(minutes: 15);
  static const int _defaultAutomaticFailureCooldownThreshold = 3;
  static const Duration _defaultAutomaticFailureCooldown = Duration(hours: 6);

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
    if (error is domain.Failure) {
      return error.message;
    }
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

  @override
  bool get isAvailable => _capabilities.supportsAutoUpdate && _feedUrl != null;

  @override
  bool get automaticSilentUpdatesEnabled =>
      _settingsStore?.getBool(AppSettingsKeys.automaticSilentUpdatesEnabled) ?? true;

  @override
  UpdateCheckDiagnostics? get lastManualDiagnostics => _lastManualDiagnostics;

  @override
  UpdateCheckDiagnostics? get lastBackgroundDiagnostics => _lastBackgroundDiagnostics;

  @override
  UpdateCheckDiagnostics? get lastAutomaticDiagnostics => _lastAutomaticDiagnostics;

  void _hydratePersistedDiagnostics() {
    final raw = _settingsStore?.getString(_lastDiagnosticsKey);
    if (raw == null || raw.isEmpty) {
      _hydratePersistedBackgroundDiagnostics();
      _hydratePersistedAutomaticDiagnostics();
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
    _hydratePersistedAutomaticDiagnostics();
  }

  void _hydratePersistedBackgroundDiagnostics() {
    final raw = _settingsStore?.getString(_lastBackgroundDiagnosticsKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
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

  void _hydratePersistedAutomaticDiagnostics() {
    final raw = _settingsStore?.getString(_lastAutomaticDiagnosticsKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _lastAutomaticDiagnostics = UpdateCheckDiagnostics.fromJson(decoded);
      }
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Failed to parse persisted automatic silent update diagnostics',
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
    if (settingsStore == null || diagnostics == null) {
      return;
    }
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
    if (settingsStore == null || diagnostics == null) {
      return;
    }
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

  Future<void> _persistLastAutomaticDiagnostics() async {
    final settingsStore = _settingsStore;
    final diagnostics = _lastAutomaticDiagnostics;
    if (settingsStore == null || diagnostics == null) {
      return;
    }
    try {
      await settingsStore.setString(
        _lastAutomaticDiagnosticsKey,
        jsonEncode(diagnostics.toJson()),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to persist automatic silent update diagnostics',
        name: 'auto_update_orchestrator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  int _consecutiveTimeoutCount() => _settingsStore?.getInt(_timeoutConsecutiveCountKey) ?? 0;

  DateTime? _timeoutCooldownUntil() {
    final timestamp = _settingsStore?.getInt(_timeoutCooldownUntilKey);
    if (timestamp == null || timestamp <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Future<void> _recordTimeoutOutcome() async {
    final settingsStore = _settingsStore;
    if (settingsStore == null) {
      return;
    }
    final nextCount = _consecutiveTimeoutCount() + 1;
    final values = <String, Object>{
      _timeoutConsecutiveCountKey: nextCount,
    };
    if (nextCount >= _timeoutCircuitThreshold) {
      final cooldownUntil = DateTime.now().add(_timeoutCircuitCooldown);
      values[_timeoutCooldownUntilKey] = cooldownUntil.millisecondsSinceEpoch;
      _metricsCollector?.recordAutoUpdateCircuitOpened();
      _logManualCheck(
        'Auto-update manual check circuit opened',
        checkId: _activeCheckId,
        level: 900,
      );
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
    if (settingsStore == null) {
      return;
    }
    final hasTimeoutCount = settingsStore.containsKey(_timeoutConsecutiveCountKey);
    final hasCooldown = settingsStore.containsKey(_timeoutCooldownUntilKey);
    if (!hasTimeoutCount && !hasCooldown) {
      return;
    }
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

  Future<Result<bool>?> _buildCircuitOpenFailure(String feedUrl) async {
    final cooldownUntil = _timeoutCooldownUntil();
    if (cooldownUntil == null) {
      return null;
    }
    final remaining = cooldownUntil.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      await _resetTimeoutCircuitIfNeeded();
      return null;
    }

    final minutesRemaining = remaining.inMinutes;
    final humanRemaining = minutesRemaining >= 1 ? '$minutesRemaining min' : '${remaining.inSeconds}s';
    final now = DateTime.now();
    final failure = Failure<bool, Exception>(
      _buildManualFailure(
        message:
            'Update checks are temporarily paused after repeated updater timeouts. '
            'Try again in about $humanRemaining.',
        completionSource: UpdateCheckCompletionSource.circuitOpen,
        context: <String, dynamic>{
          'cooldown_remaining_ms': remaining.inMilliseconds,
        },
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

  int _automaticFailureCount() => _settingsStore?.getInt(_automaticFailureCountKey) ?? 0;

  DateTime? _automaticCooldownUntil() {
    final timestamp = _settingsStore?.getInt(_automaticCooldownUntilKey);
    if (timestamp == null || timestamp <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Future<void> _resetAutomaticFailureCooldownIfNeeded() async {
    final settingsStore = _settingsStore;
    if (settingsStore == null) {
      return;
    }
    final hasFailureCount = settingsStore.containsKey(_automaticFailureCountKey);
    final hasCooldown = settingsStore.containsKey(_automaticCooldownUntilKey);
    if (!hasFailureCount && !hasCooldown) {
      return;
    }
    try {
      await settingsStore.remove(_automaticFailureCountKey);
      await settingsStore.remove(_automaticCooldownUntilKey);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to reset automatic silent update cooldown state',
        name: 'auto_update_orchestrator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<({int failureCount, DateTime? cooldownUntil})> _recordAutomaticFailureAndApplyCooldown() async {
    final settingsStore = _settingsStore;
    if (settingsStore == null) {
      return (failureCount: 0, cooldownUntil: null);
    }
    final nextCount = _automaticFailureCount() + 1;
    DateTime? cooldownUntil;
    final values = <String, Object>{
      _automaticFailureCountKey: nextCount,
    };
    if (nextCount >= _automaticFailureCooldownThreshold) {
      cooldownUntil = DateTime.now().add(_automaticFailureCooldown);
      values[_automaticCooldownUntilKey] = cooldownUntil.millisecondsSinceEpoch;
    }
    try {
      await settingsStore.setValues(values);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to persist automatic silent update cooldown state',
        name: 'auto_update_orchestrator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
    return (failureCount: nextCount, cooldownUntil: cooldownUntil);
  }

  Future<Result<bool>?> _buildAutomaticCooldownResult(String feedUrl) async {
    final cooldownUntil = _automaticCooldownUntil();
    if (cooldownUntil == null) {
      return null;
    }
    final remaining = cooldownUntil.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      await _resetAutomaticFailureCooldownIfNeeded();
      return null;
    }

    final minutesRemaining = remaining.inMinutes;
    final humanRemaining = minutesRemaining >= 1 ? '$minutesRemaining min' : '${remaining.inSeconds}s';
    final now = DateTime.now();
    _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
      checkedAt: now,
      configuredFeedUrl: feedUrl,
      requestedFeedUrl: feedUrl,
      currentVersion: AppConstants.appVersion,
      completedAt: now,
      completionSource: UpdateCheckCompletionSource.automaticCooldown,
      updateAvailable: false,
      automaticFailureCount: _automaticFailureCount(),
      automaticCooldownUntil: cooldownUntil,
      errorMessage: 'Automatic silent updates are paused after repeated failures. Try again in about $humanRemaining.',
    );
    await _persistLastAutomaticDiagnostics();
    return const Success<bool, Exception>(false);
  }

  Future<void> _cleanupSilentUpdateArtifacts(ISilentUpdateInstaller installer) async {
    final cleanupResult = await installer.cleanupObsoleteArtifacts();
    cleanupResult.fold(
      (_) {},
      (error) {
        developer.log(
          'Silent update artifact cleanup failed',
          name: 'auto_update_orchestrator',
          level: 900,
          error: error,
        );
      },
    );
  }

  int _rolloutBucket() {
    final existing = _settingsStore?.getInt(_automaticRolloutBucketKey);
    if (existing != null && existing >= 0 && existing < 100) {
      return existing;
    }
    final generated = Random.secure().nextInt(100);
    final settingsStore = _settingsStore;
    if (settingsStore != null) {
      unawaited(settingsStore.setInt(_automaticRolloutBucketKey, generated));
    }
    return generated;
  }

  bool _isProbeEligibleForConfiguredChannel(AppcastProbeResult result) {
    final configuredChannel = resolveAutoUpdateChannel(environment: AppEnvironment.snapshot());
    final remoteChannel = (result.channel == null || result.channel!.isEmpty)
        ? defaultAutoUpdateChannel
        : result.channel!.toLowerCase();
    if (remoteChannel != configuredChannel) {
      return false;
    }
    final rolloutPercentage = result.rolloutPercentage ?? 100;
    return rolloutPercentage >= 100 || _rolloutBucket() < rolloutPercentage;
  }

  void _recordCompletionMetric(UpdateCheckCompletionSource source) {
    final metricsCollector = _metricsCollector;
    if (metricsCollector == null) {
      return;
    }
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
        break;
    }
  }

  UpdateCheckDiagnostics _buildBackgroundDiagnostics(String feedUrl) {
    final now = DateTime.now();
    return UpdateCheckDiagnostics(
      checkedAt: now,
      configuredFeedUrl: feedUrl,
      requestedFeedUrl: feedUrl,
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
          context: <String, dynamic>{
            'operation': 'setAutomaticSilentUpdatesEnabled',
          },
        ),
      );
    }

    try {
      await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, enabled);
      if (_isInitialized) {
        final intervalSeconds = enabled
            ? 0
            : resolveAutoUpdateCheckIntervalSeconds(
                environment: AppEnvironment.snapshot(),
              );
        await _updaterGateway.setScheduledCheckInterval(intervalSeconds);
      }
      if (!enabled) {
        _automaticCheckTimer?.cancel();
        _automaticCheckTimer = null;
      } else {
        _scheduleAutomaticSilentChecks(runImmediately: true);
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
    if (!isAvailable) {
      return;
    }

    await initialize();
    await _reconcilePendingSilentUpdate();
    _automaticCheckTimer?.cancel();
    _automaticCheckTimer = null;

    if (automaticSilentUpdatesEnabled) {
      _scheduleAutomaticSilentChecks(runImmediately: true);
      return;
    }

    unawaited(checkInBackground());
  }

  void _scheduleAutomaticSilentChecks({required bool runImmediately}) {
    _automaticCheckTimer?.cancel();
    _automaticCheckTimer = null;

    if (runImmediately) {
      unawaited(checkSilently());
    }

    final intervalSeconds = resolveAutoUpdateCheckIntervalSeconds(
      environment: AppEnvironment.snapshot(),
    );
    if (intervalSeconds > 0) {
      _automaticCheckTimer = Timer.periodic(
        Duration(seconds: intervalSeconds),
        (_) => unawaited(checkSilently()),
      );
    }
  }

  @override
  Future<Result<bool>> checkSilently() async {
    if (_isSilentCheckInProgress) {
      return const Success<bool, Exception>(false);
    }

    final feedUrl = _feedUrl;
    if (!_capabilities.supportsAutoUpdate || feedUrl == null) {
      return Failure<bool, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Silent auto-update is not available',
          context: <String, dynamic>{'operation': 'checkSilently'},
        ),
      );
    }

    if (!automaticSilentUpdatesEnabled) {
      final now = DateTime.now();
      _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
        checkedAt: now,
        configuredFeedUrl: feedUrl,
        requestedFeedUrl: feedUrl,
        currentVersion: AppConstants.appVersion,
        completedAt: now,
        completionSource: UpdateCheckCompletionSource.automaticDisabled,
        updateAvailable: false,
      );
      await _persistLastAutomaticDiagnostics();
      return const Success<bool, Exception>(false);
    }

    final installer = _silentUpdateInstaller;
    if (installer == null) {
      final now = DateTime.now();
      _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
        checkedAt: now,
        configuredFeedUrl: feedUrl,
        requestedFeedUrl: feedUrl,
        currentVersion: AppConstants.appVersion,
        completedAt: now,
        completionSource: UpdateCheckCompletionSource.automaticInstallFailure,
        errorMessage: 'Silent update installer is not configured',
      );
      await _persistLastAutomaticDiagnostics();
      return Failure<bool, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Silent update installer is not configured',
          context: <String, dynamic>{'operation': 'checkSilently'},
        ),
      );
    }

    final pending = _readPendingSilentUpdate();
    if (pending != null) {
      final now = DateTime.now();
      final launcherStatus = _readLauncherStatus(pending.launcherStatusPath);
      _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
        checkedAt: now,
        configuredFeedUrl: feedUrl,
        requestedFeedUrl: feedUrl,
        currentVersion: AppConstants.appVersion,
        completedAt: now,
        completionSource: UpdateCheckCompletionSource.automaticInstallStarted,
        pendingVersion: pending.version,
        installerPath: launcherStatus?.installerPath ?? pending.installerPath,
        installerLogPath: launcherStatus?.logPath ?? pending.logPath,
        installDirectory: launcherStatus?.installDirectory ?? pending.installDirectory,
        silentUpdateStrategy: launcherStatus?.strategy ?? pending.strategy,
        launcherPath: pending.launcherPath,
        launcherStatusPath: pending.launcherStatusPath,
        launcherState: launcherStatus?.state,
        nonAdminExitCode: launcherStatus?.nonAdminExitCode,
        nonAdminDurationMs: launcherStatus?.nonAdminDurationMs,
        elevatedExitCode: launcherStatus?.elevatedExitCode,
        elevatedDurationMs: launcherStatus?.elevatedDurationMs,
        elevatedRetryStarted: launcherStatus?.elevatedRetryStarted,
        waitForAppExitDurationMs: launcherStatus?.waitForAppExitDurationMs,
        appPid: launcherStatus?.appPid ?? pending.appPid,
        signatureStatus: launcherStatus?.signatureStatus,
        signatureRequired: launcherStatus?.signatureRequired,
        updateDirectorySecurityStatus: pending.updateDirectorySecurityStatus,
        actualSha256: launcherStatus?.actualSha256,
        hashValidationStatus: launcherStatus?.hashValidationStatus,
        installDirectoryWritable: launcherStatus?.installDirectoryWritable,
        elevatedCancelled: launcherStatus?.elevatedCancelled,
        errorMessage: 'Silent update already has a pending installer execution',
      );
      await _persistLastAutomaticDiagnostics();
      return const Success<bool, Exception>(false);
    }

    await _cleanupSilentUpdateArtifacts(installer);
    final cooldownResult = await _buildAutomaticCooldownResult(feedUrl);
    if (cooldownResult != null) {
      return cooldownResult;
    }

    _isSilentCheckInProgress = true;
    final startedAt = DateTime.now();
    _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
      checkedAt: startedAt,
      configuredFeedUrl: feedUrl,
      requestedFeedUrl: feedUrl,
      currentVersion: AppConstants.appVersion,
      probeRequestUrl: feedUrl,
    );
    await _persistLastAutomaticDiagnostics();

    try {
      final probeResult = await _appcastProbeService.probeLatest(feedUrl: feedUrl);
      _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
        probeRequestUrl: probeResult.requestUrl,
        probeSucceeded: probeResult.errorMessage == null,
        appcastProbeVersion: probeResult.latestVersion,
        appcastProbeItemCount: probeResult.itemCount,
        remoteVersion: probeResult.latestVersion,
        remoteDisplayVersion: probeResult.latestVersion,
        assetUrl: probeResult.assetUrl,
        assetSize: probeResult.assetSize,
        assetName: probeResult.assetName,
        sha256: probeResult.sha256,
        rolloutChannel: probeResult.channel ?? defaultAutoUpdateChannel,
        rolloutPercentage: probeResult.rolloutPercentage ?? 100,
        rolloutBucket: _rolloutBucket(),
        probeErrorMessage: probeResult.errorMessage,
      );

      if (probeResult.errorMessage != null) {
        final now = DateTime.now();
        final failureState = await _recordAutomaticFailureAndApplyCooldown();
        _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticDownloadFailure,
          automaticFailureCount: failureState.failureCount,
          automaticCooldownUntil: failureState.cooldownUntil,
          errorMessage: probeResult.errorMessage,
        );
        await _persistLastAutomaticDiagnostics();
        return Failure<bool, Exception>(
          domain.NetworkFailure.withContext(
            message: 'Silent update appcast probe failed',
            context: <String, dynamic>{
              'operation': 'checkSilently',
              'feed_url': feedUrl,
              'probe_error': probeResult.errorMessage,
            },
          ),
        );
      }

      final validationError = _validateSilentProbeResult(probeResult);
      if (validationError != null) {
        final now = DateTime.now();
        final failureState = await _recordAutomaticFailureAndApplyCooldown();
        _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticValidationFailure,
          automaticFailureCount: failureState.failureCount,
          automaticCooldownUntil: failureState.cooldownUntil,
          errorMessage: validationError,
        );
        await _persistLastAutomaticDiagnostics();
        return Failure<bool, Exception>(
          domain.ValidationFailure.withContext(
            message: validationError,
            context: <String, dynamic>{
              'operation': 'checkSilently',
              'feed_url': feedUrl,
            },
          ),
        );
      }

      final remoteVersion = probeResult.latestVersion!;
      final rolloutEligible = _isProbeEligibleForConfiguredChannel(probeResult);
      _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
        rolloutEligible: rolloutEligible,
      );
      if (!rolloutEligible) {
        final now = DateTime.now();
        await _resetAutomaticFailureCooldownIfNeeded();
        _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticRolloutSkipped,
          updateAvailable: false,
        );
        await _persistLastAutomaticDiagnostics();
        return const Success<bool, Exception>(false);
      }

      final isNewer = AppVersionComparator.isRemoteVersionNewer(
        remoteVersion: remoteVersion,
        currentVersion: AppConstants.appVersion,
      );
      if (!isNewer) {
        final now = DateTime.now();
        await _resetAutomaticFailureCooldownIfNeeded();
        _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticUpdateNotAvailable,
          updateAvailable: false,
        );
        await _persistLastAutomaticDiagnostics();
        return const Success<bool, Exception>(false);
      }

      final pendingUpdate = _PendingSilentUpdate(
        version: remoteVersion,
        installerPath: null,
        logPath: null,
        installDirectory: null,
        strategy: null,
        launcherPath: null,
        launcherStatusPath: null,
        appPid: null,
        updateDirectorySecurityStatus: null,
        startedAt: DateTime.now(),
      );
      await _persistPendingSilentUpdate(pendingUpdate);
      _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
        updateAvailable: true,
        pendingVersion: remoteVersion,
        triggerStartedAt: DateTime.now(),
      );
      await _persistLastAutomaticDiagnostics();

      final installResult = await installer.install(
        SilentUpdateInstallRequest(
          version: remoteVersion,
          assetUrl: probeResult.assetUrl!,
          assetSize: probeResult.assetSize!,
          assetName: probeResult.assetName!,
          sha256: probeResult.sha256!,
          requireValidSignature: resolveAutoUpdateRequireValidSignature(
            environment: AppEnvironment.snapshot(),
          ),
        ),
      );

      SilentUpdateInstallResult? installSuccess;
      Exception? installError;
      installResult.fold(
        (value) => installSuccess = value,
        (error) => installError = error,
      );

      final now = DateTime.now();
      if (installError != null) {
        await _clearPendingSilentUpdate();
        final completionSource = installError is domain.NetworkFailure
            ? UpdateCheckCompletionSource.automaticDownloadFailure
            : installError is domain.ValidationFailure
            ? UpdateCheckCompletionSource.automaticValidationFailure
            : UpdateCheckCompletionSource.automaticInstallFailure;
        final failureState = await _recordAutomaticFailureAndApplyCooldown();
        _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
          triggerCompletedAt: now,
          completedAt: now,
          completionSource: completionSource,
          automaticFailureCount: failureState.failureCount,
          automaticCooldownUntil: failureState.cooldownUntil,
          errorMessage: _extractFailureMessage(installError!),
        );
        await _persistLastAutomaticDiagnostics();
        return Failure<bool, Exception>(installError!);
      }

      final success = installSuccess!;
      await _persistPendingSilentUpdate(
        _PendingSilentUpdate(
          version: remoteVersion,
          installerPath: success.installerPath,
          logPath: success.logPath,
          installDirectory: success.installDirectory,
          strategy: success.strategy.name,
          launcherPath: success.launcherPath,
          launcherStatusPath: success.launcherStatusPath,
          appPid: success.appPid,
          updateDirectorySecurityStatus: success.updateDirectorySecurityStatus,
          startedAt: DateTime.now(),
        ),
      );
      await _resetAutomaticFailureCooldownIfNeeded();
      _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
        triggerCompletedAt: now,
        completedAt: now,
        completionSource: UpdateCheckCompletionSource.automaticInstallStarted,
        installerPath: success.installerPath,
        installerLogPath: success.logPath,
        installDirectory: success.installDirectory,
        silentUpdateStrategy: success.strategy.name,
        launcherPath: success.launcherPath,
        launcherStatusPath: success.launcherStatusPath,
        appPid: success.appPid,
        updateDirectorySecurityStatus: success.updateDirectorySecurityStatus,
        installDirectoryWritable: success.installDirectoryWritable,
        signatureRequired: resolveAutoUpdateRequireValidSignature(
          environment: AppEnvironment.snapshot(),
        ),
      );
      await _persistLastAutomaticDiagnostics();
      await _settingsStore?.flushPendingPersistence();
      final closeApplication = _closeApplicationForSilentUpdate;
      if (closeApplication != null) {
        unawaited(closeApplication());
      }
      return const Success<bool, Exception>(true);
    } on FormatException catch (error) {
      final now = DateTime.now();
      final failureState = await _recordAutomaticFailureAndApplyCooldown();
      _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
        completedAt: now,
        completionSource: UpdateCheckCompletionSource.automaticValidationFailure,
        automaticFailureCount: failureState.failureCount,
        automaticCooldownUntil: failureState.cooldownUntil,
        errorMessage: error.message,
      );
      await _persistLastAutomaticDiagnostics();
      return Failure<bool, Exception>(
        domain.ValidationFailure.withContext(
          message: error.message,
          cause: error,
          context: <String, dynamic>{'operation': 'checkSilently'},
        ),
      );
    } finally {
      _isSilentCheckInProgress = false;
    }
  }

  String? _validateSilentProbeResult(AppcastProbeResult result) {
    final version = result.latestVersion?.trim();
    if (version == null || version.isEmpty) {
      return 'Silent update appcast is missing the latest version';
    }
    final assetUrl = result.assetUrl?.trim();
    if (assetUrl == null || assetUrl.isEmpty) {
      return 'Silent update appcast is missing the installer URL';
    }
    final assetSize = result.assetSize;
    if (assetSize == null || assetSize <= 0) {
      return 'Silent update appcast is missing a valid installer size';
    }
    final assetName = result.assetName?.trim();
    if (assetName == null || assetName.isEmpty || !assetName.toLowerCase().endsWith('.exe')) {
      return 'Silent update appcast is missing a valid installer name';
    }
    final sha256 = result.sha256?.trim().toLowerCase();
    if (sha256 == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      return 'Silent update appcast is missing a valid plug:sha256 digest';
    }
    final rolloutPercentage = result.rolloutPercentage;
    if (rolloutPercentage != null && (rolloutPercentage < 0 || rolloutPercentage > 100)) {
      return 'Silent update appcast has an invalid plug:rolloutPercentage value';
    }
    return null;
  }

  Future<void> _reconcilePendingSilentUpdate() async {
    final pending = _readPendingSilentUpdate();
    if (pending == null) {
      return;
    }
    final feedUrl = _feedUrl ?? officialAutoUpdateFeedUrl;
    final now = DateTime.now();
    final launcherStatus = _readLauncherStatus(pending.launcherStatusPath);
    bool completed;
    try {
      completed =
          AppVersionComparator.compare(
            AppConstants.appVersion,
            pending.version,
          ) >=
          0;
    } on FormatException {
      completed = false;
    }
    if (!completed && _shouldKeepPendingSilentUpdate(pending, launcherStatus, now)) {
      _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
        checkedAt: now,
        configuredFeedUrl: feedUrl,
        requestedFeedUrl: feedUrl,
        currentVersion: AppConstants.appVersion,
        completedAt: now,
        completionSource: UpdateCheckCompletionSource.automaticInstallStarted,
        updateAvailable: true,
        pendingVersion: pending.version,
        installerPath: launcherStatus?.installerPath ?? pending.installerPath,
        installerLogPath: launcherStatus?.logPath ?? pending.logPath,
        installDirectory: launcherStatus?.installDirectory ?? pending.installDirectory,
        silentUpdateStrategy: launcherStatus?.strategy ?? pending.strategy,
        launcherPath: pending.launcherPath,
        launcherStatusPath: pending.launcherStatusPath,
        launcherState: launcherStatus?.state,
        nonAdminExitCode: launcherStatus?.nonAdminExitCode,
        nonAdminDurationMs: launcherStatus?.nonAdminDurationMs,
        elevatedExitCode: launcherStatus?.elevatedExitCode,
        elevatedDurationMs: launcherStatus?.elevatedDurationMs,
        elevatedRetryStarted: launcherStatus?.elevatedRetryStarted,
        waitForAppExitDurationMs: launcherStatus?.waitForAppExitDurationMs,
        appPid: launcherStatus?.appPid ?? pending.appPid,
        signatureStatus: launcherStatus?.signatureStatus,
        signatureRequired: launcherStatus?.signatureRequired,
        updateDirectorySecurityStatus: pending.updateDirectorySecurityStatus,
        actualSha256: launcherStatus?.actualSha256,
        hashValidationStatus: launcherStatus?.hashValidationStatus,
        installDirectoryWritable: launcherStatus?.installDirectoryWritable,
        elevatedCancelled: launcherStatus?.elevatedCancelled,
        errorMessage: 'Silent update installer is still running',
      );
      await _persistLastAutomaticDiagnostics();
      return;
    }
    final failureState = completed ? null : await _recordAutomaticFailureAndApplyCooldown();
    if (completed) {
      await _resetAutomaticFailureCooldownIfNeeded();
    }
    _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
      checkedAt: now,
      configuredFeedUrl: feedUrl,
      requestedFeedUrl: feedUrl,
      currentVersion: AppConstants.appVersion,
      completedAt: now,
      completionSource: completed
          ? UpdateCheckCompletionSource.automaticPendingCompleted
          : UpdateCheckCompletionSource.automaticPendingFailed,
      updateAvailable: !completed,
      pendingVersion: pending.version,
      installerPath: launcherStatus?.installerPath ?? pending.installerPath,
      installerLogPath: launcherStatus?.logPath ?? pending.logPath,
      installDirectory: launcherStatus?.installDirectory ?? pending.installDirectory,
      silentUpdateStrategy: launcherStatus?.strategy ?? pending.strategy,
      launcherPath: pending.launcherPath,
      launcherStatusPath: pending.launcherStatusPath,
      launcherState: launcherStatus?.state,
      nonAdminExitCode: launcherStatus?.nonAdminExitCode,
      nonAdminDurationMs: launcherStatus?.nonAdminDurationMs,
      elevatedExitCode: launcherStatus?.elevatedExitCode,
      elevatedDurationMs: launcherStatus?.elevatedDurationMs,
      elevatedRetryStarted: launcherStatus?.elevatedRetryStarted,
      waitForAppExitDurationMs: launcherStatus?.waitForAppExitDurationMs,
      appPid: launcherStatus?.appPid ?? pending.appPid,
      signatureStatus: launcherStatus?.signatureStatus,
      signatureRequired: launcherStatus?.signatureRequired,
      updateDirectorySecurityStatus: pending.updateDirectorySecurityStatus,
      actualSha256: launcherStatus?.actualSha256,
      hashValidationStatus: launcherStatus?.hashValidationStatus,
      installDirectoryWritable: launcherStatus?.installDirectoryWritable,
      elevatedCancelled: launcherStatus?.elevatedCancelled,
      automaticFailureCount: failureState?.failureCount,
      automaticCooldownUntil: failureState?.cooldownUntil,
      errorMessage: completed ? null : launcherStatus?.failureMessage ?? 'Pending silent update did not complete',
    );
    await _persistLastAutomaticDiagnostics();
    await _clearPendingSilentUpdate();
  }

  bool _shouldKeepPendingSilentUpdate(
    _PendingSilentUpdate pending,
    _SilentUpdateLauncherStatus? launcherStatus,
    DateTime now,
  ) {
    const maxPendingInstallerAge = Duration(minutes: 30);
    final startedAt = launcherStatus?.lastUpdatedAt ?? pending.startedAt;
    if (startedAt == null || now.difference(startedAt) > maxPendingInstallerAge) {
      return false;
    }
    final state = launcherStatus?.state;
    return state == null ||
        state == 'started' ||
        state == 'waitingForAppExit' ||
        state == 'nonAdminStarted' ||
        state == 'elevatedStarted';
  }

  _PendingSilentUpdate? _readPendingSilentUpdate() {
    final raw = _settingsStore?.getString(_pendingSilentUpdateKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return _PendingSilentUpdate.fromJson(decoded);
      }
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Failed to parse pending silent update state',
        name: 'auto_update_orchestrator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
    return null;
  }

  Future<void> _persistPendingSilentUpdate(_PendingSilentUpdate pending) async {
    await _settingsStore?.setString(
      _pendingSilentUpdateKey,
      jsonEncode(pending.toJson()),
    );
  }

  Future<void> _clearPendingSilentUpdate() async {
    await _settingsStore?.remove(_pendingSilentUpdateKey);
  }

  _SilentUpdateLauncherStatus? _readLauncherStatus(String? statusPath) {
    if (statusPath == null || statusPath.isEmpty) {
      return null;
    }
    try {
      final statusFile = File(statusPath);
      if (!statusFile.existsSync()) {
        return null;
      }
      final decoded = jsonDecode(statusFile.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        return _SilentUpdateLauncherStatus.fromJson(decoded);
      }
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to read silent update launcher status',
        name: 'auto_update_orchestrator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
    return null;
  }

  static const int _defaultBackgroundRetryLimit = 3;
  static const Duration _defaultBackgroundRetryBaseDelay = Duration(seconds: 30);

  @override
  Future<void> checkInBackground() async {
    if (!isAvailable) return;
    if (automaticSilentUpdatesEnabled) {
      await checkSilently();
      return;
    }
    final feedUrl = _feedUrl;
    if (feedUrl == null) {
      return;
    }
    for (var attempt = 1; attempt <= _backgroundRetryLimit; attempt++) {
      _lastBackgroundDiagnostics = _buildBackgroundDiagnostics(feedUrl);
      try {
        await _updaterGateway.checkForUpdates(inBackground: true);
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
          final delay = _backgroundRetryBaseDelay * attempt;
          developer.log(
            'Retrying in ${delay.inSeconds}s',
            name: 'auto_update_orchestrator',
            level: 800,
          );
          await Future<void>.delayed(delay);
        }
      }
    }
  }

  static const Duration _defaultManualTriggerTimeout = Duration(seconds: 15);
  static const Duration _defaultManualCompletionTimeout = Duration(seconds: 60);

  @override
  Future<Result<bool>> checkManual() async {
    if (!_capabilities.supportsAutoUpdate) {
      return Failure<bool, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Auto-update is not supported in current runtime mode',
          context: {'operation': 'checkManual'},
        ),
      );
    }

    final feedUrl = _feedUrl;
    if (feedUrl == null) {
      return Failure<bool, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Update feed URL is not configured',
          context: {'operation': 'checkManual'},
        ),
      );
    }

    final circuitOpenFailure = await _buildCircuitOpenFailure(feedUrl);
    if (circuitOpenFailure != null) {
      return circuitOpenFailure;
    }

    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized) {
        final failure = Failure<bool, Exception>(
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
      return Failure<bool, Exception>(
        domain.ServerFailure.withContext(
          message: 'Update check already in progress',
          context: {'operation': 'checkManual'},
        ),
      );
    }

    _manualCheckCompleter = Completer<Result<bool>>();
    _isManualCheck = true;
    _activeCheckId = 'manual-${DateTime.now().millisecondsSinceEpoch}';
    final manualFeedUrl = _buildManualFeedUrl(feedUrl);
    _metricsCollector?.recordAutoUpdateManualCheckStarted();
    _activeManualDiagnostics = UpdateCheckDiagnostics(
      checkedAt: DateTime.now(),
      configuredFeedUrl: feedUrl,
      requestedFeedUrl: manualFeedUrl,
      currentVersion: AppConstants.appVersion,
      probeRequestUrl: manualFeedUrl,
    );
    try {
      _logManualCheck(
        'Manual update check triggered',
        checkId: _activeCheckId,
      );
      final probeResult = await _appcastProbeService.probeLatest(
        feedUrl: manualFeedUrl,
      );
      _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
        probeRequestUrl: probeResult.requestUrl,
        probeSucceeded: probeResult.errorMessage == null,
        appcastProbeVersion: probeResult.latestVersion,
        appcastProbeItemCount: probeResult.itemCount,
        probeErrorMessage: probeResult.errorMessage,
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
          final failure = Failure<bool, Exception>(
            _buildManualFailure(
              message: 'Update check timed out while waiting for updater completion',
              completionSource: UpdateCheckCompletionSource.completionTimeout,
            ),
          );
          _completeManualCheck(
            failure,
            completionSource: UpdateCheckCompletionSource.completionTimeout,
          );
          return failure;
        },
      );
    } on TimeoutException catch (e) {
      final now = DateTime.now();
      _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
        triggerCompletedAt: now,
      );
      final failure = Failure<bool, Exception>(
        _buildManualFailure(
          message: 'Update check trigger timed out before updater responded',
          completionSource: UpdateCheckCompletionSource.triggerTimeout,
          cause: e,
        ),
      );
      _completeManualCheck(
        failure,
        completionSource: UpdateCheckCompletionSource.triggerTimeout,
      );
      return failure;
    } on Exception catch (e) {
      final failure = Failure<bool, Exception>(
        _buildManualFailure(
          message: 'Failed to trigger update check',
          cause: e,
          completionSource: UpdateCheckCompletionSource.triggerFailure,
        ),
      );
      _completeManualCheck(
        failure,
        completionSource: UpdateCheckCompletionSource.triggerFailure,
      );
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
    }
  }

  void _completeManualCheck(
    Result<bool> result, {
    UpdateCheckCompletionSource? completionSource,
  }) {
    final completedAt = DateTime.now();
    final isTrackedManualCheck = _activeManualDiagnostics != null;
    result.fold(
      (isUpdateAvailable) {
        final resolvedCompletionSource =
            completionSource ??
            (isUpdateAvailable
                ? UpdateCheckCompletionSource.updateAvailable
                : UpdateCheckCompletionSource.updateNotAvailable);
        _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
          completedAt: completedAt,
          completionSource: resolvedCompletionSource,
          updateAvailable: isUpdateAvailable,
        );
        if (isTrackedManualCheck) {
          _recordCompletionMetric(resolvedCompletionSource);
        }
      },
      (error) {
        final resolvedCompletionSource = completionSource ?? UpdateCheckCompletionSource.updaterError;
        _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
          completedAt: completedAt,
          completionSource: resolvedCompletionSource,
          errorMessage: _extractFailureMessage(error),
        );
        if (isTrackedManualCheck) {
          _recordCompletionMetric(resolvedCompletionSource);
        }
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
      _logManualCheck(
        'Manual update check completed',
        checkId: _activeCheckId,
      );
    }
    if (_isManualCheck && _manualCheckCompleter != null && !_manualCheckCompleter!.isCompleted) {
      _manualCheckCompleter!.complete(result);
    }
  }

  @override
  void onUpdaterError(UpdaterError? error) {
    if (!_isManualCheck) {
      _lastBackgroundDiagnostics = _backgroundDiagnosticsOrDefault().copyWith(
        completedAt: DateTime.now(),
        completionSource: UpdateCheckCompletionSource.updaterError,
        errorMessage: error?.toString() ?? 'Update check failed',
      );
      _metricsCollector?.recordAutoUpdateBackgroundCheckUpdaterError();
      unawaited(_persistLastBackgroundDiagnostics());
      developer.log(
        'Background auto-updater error: $error',
        name: 'auto_update_orchestrator',
        level: 900,
      );
      return;
    }
    _logManualCheck(
      'Auto-updater error: $error',
      checkId: _activeCheckId,
      level: 900,
    );
    _completeManualCheck(
      Failure<bool, Exception>(
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
    _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
      remoteVersion: appcastItem?.versionString,
      remoteDisplayVersion: appcastItem?.displayVersionString,
    );
    _completeManualCheck(
      const Success(true),
      completionSource: UpdateCheckCompletionSource.updateAvailable,
    );
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    if (!_isManualCheck) {
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
    if (error != null) {
      _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
        errorMessage: error.message,
      );
    }
    _completeManualCheck(
      const Success(false),
      completionSource: UpdateCheckCompletionSource.updateNotAvailable,
    );
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    _logManualCheck(
      'Update downloaded: ${appcastItem?.versionString}',
      checkId: _activeCheckId,
    );
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    _logManualCheck(
      'Before quit for update: ${appcastItem?.versionString}',
      checkId: _activeCheckId,
    );
    windowManager.setPreventClose(false);
  }
}

class _PendingSilentUpdate {
  const _PendingSilentUpdate({
    required this.version,
    required this.installerPath,
    required this.logPath,
    required this.installDirectory,
    required this.strategy,
    required this.launcherPath,
    required this.launcherStatusPath,
    required this.appPid,
    required this.updateDirectorySecurityStatus,
    required this.startedAt,
  });

  final String version;
  final String? installerPath;
  final String? logPath;
  final String? installDirectory;
  final String? strategy;
  final String? launcherPath;
  final String? launcherStatusPath;
  final int? appPid;
  final String? updateDirectorySecurityStatus;
  final DateTime? startedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': version,
      'installerPath': installerPath,
      'logPath': logPath,
      'installDirectory': installDirectory,
      'strategy': strategy,
      'launcherPath': launcherPath,
      'launcherStatusPath': launcherStatusPath,
      'appPid': appPid,
      'updateDirectorySecurityStatus': updateDirectorySecurityStatus,
      'startedAt': (startedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  static _PendingSilentUpdate? fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! String || version.isEmpty) {
      return null;
    }
    return _PendingSilentUpdate(
      version: version,
      installerPath: json['installerPath'] as String?,
      logPath: json['logPath'] as String?,
      installDirectory: json['installDirectory'] as String?,
      strategy: json['strategy'] as String?,
      launcherPath: json['launcherPath'] as String?,
      launcherStatusPath: json['launcherStatusPath'] as String?,
      appPid: _readInt(json['appPid']),
      updateDirectorySecurityStatus: json['updateDirectorySecurityStatus'] as String?,
      startedAt: _readDateTime(json['startedAt']),
    );
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}

class _SilentUpdateLauncherStatus {
  const _SilentUpdateLauncherStatus({
    required this.state,
    required this.strategy,
    required this.installDirectory,
    required this.installerPath,
    required this.logPath,
    required this.nonAdminExitCode,
    required this.nonAdminDurationMs,
    required this.elevatedExitCode,
    required this.elevatedDurationMs,
    required this.elevatedRetryStarted,
    required this.waitForAppExitDurationMs,
    required this.appPid,
    required this.signatureStatus,
    required this.signatureRequired,
    required this.actualSha256,
    required this.hashValidationStatus,
    required this.installDirectoryWritable,
    required this.elevatedCancelled,
    required this.errorMessage,
    required this.lastUpdatedAt,
  });

  final String? state;
  final String? strategy;
  final String? installDirectory;
  final String? installerPath;
  final String? logPath;
  final int? nonAdminExitCode;
  final int? nonAdminDurationMs;
  final int? elevatedExitCode;
  final int? elevatedDurationMs;
  final bool? elevatedRetryStarted;
  final int? waitForAppExitDurationMs;
  final int? appPid;
  final String? signatureStatus;
  final bool? signatureRequired;
  final String? actualSha256;
  final String? hashValidationStatus;
  final bool? installDirectoryWritable;
  final bool? elevatedCancelled;
  final String? errorMessage;
  final DateTime? lastUpdatedAt;

  String? get failureMessage {
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      return errorMessage;
    }
    if (state != null && state!.isNotEmpty) {
      return 'Launcher status: $state';
    }
    return null;
  }

  static _SilentUpdateLauncherStatus fromJson(Map<String, dynamic> json) {
    return _SilentUpdateLauncherStatus(
      state: json['state'] as String?,
      strategy: json['strategy'] as String?,
      installDirectory: json['installDirectory'] as String?,
      installerPath: json['installerPath'] as String?,
      logPath: json['logPath'] as String?,
      nonAdminExitCode: _readInt(json['nonAdminExitCode']),
      nonAdminDurationMs: _readInt(json['nonAdminDurationMs']),
      elevatedExitCode: _readInt(json['elevatedExitCode']),
      elevatedDurationMs: _readInt(json['elevatedDurationMs']),
      elevatedRetryStarted: json['elevatedRetryStarted'] as bool?,
      waitForAppExitDurationMs: _readInt(json['waitForAppExitDurationMs']),
      appPid: _readInt(json['appPid']),
      signatureStatus: json['signatureStatus'] as String?,
      signatureRequired: json['signatureRequired'] as bool?,
      actualSha256: json['actualSha256'] as String?,
      hashValidationStatus: json['hashValidationStatus'] as String?,
      installDirectoryWritable: json['installDirectoryWritable'] as bool?,
      elevatedCancelled: json['elevatedCancelled'] as bool?,
      errorMessage: json['errorMessage'] as String?,
      lastUpdatedAt: _readDateTime(json['lastUpdatedAt']),
    );
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}
