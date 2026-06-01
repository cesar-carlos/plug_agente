import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:auto_updater/auto_updater.dart';
import 'package:plug_agente/application/observability/i_auto_update_diagnostics_gateway.dart';
import 'package:plug_agente/application/observability/i_auto_update_metrics_collector.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/observability/update_check_id_recorder.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/auto_update_failure_messages.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator_options.dart';
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
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/i_uac_detector.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Boundary the application layer uses to talk to WinSparkle. Avoids
/// the orchestrator importing the platform-channel plugin types
/// directly. Tests inject a fake; the production registrar wires the
/// real adapter [AutoUpdaterGateway] backed by `package:auto_updater`.
abstract interface class IAutoUpdaterGateway {
  /// Backward-compatible direct listener subscription. New consumers
  /// should prefer [events] (sealed [UpdaterEvent] stream) instead, so
  /// they do not depend on the plugin's `UpdaterListener` mixin.
  void addListener(UpdaterListener listener);

  /// Broadcast stream of sealed [UpdaterEvent]s translated from the
  /// underlying plugin callbacks. Multiple subscribers are allowed and
  /// the stream lives for the gateway lifetime.
  Stream<UpdaterEvent> get events;

  Future<void> setFeedURL(String feedUrl);
  Future<void> checkForUpdates({required bool inBackground});
  Future<void> setScheduledCheckInterval(int interval);
}

/// Production adapter for WinSparkle. Hides the plugin behind the
/// sealed [UpdaterEvent] surface; the orchestrator subscribes to
/// [events] instead of mixing `UpdaterListener` into its own type.
///
/// The constructor is intentionally cheap (no plugin calls): the
/// translator is only attached to `autoUpdater` on the first access to
/// [events]. That keeps test/non-Windows code paths that build the
/// orchestrator (e.g. degraded runtime checks) free from platform
/// channel errors.
class AutoUpdaterGateway implements IAutoUpdaterGateway {
  AutoUpdaterGateway();

  _UpdaterEventTranslator? _translator;

  @override
  void addListener(UpdaterListener listener) {
    autoUpdater.addListener(listener);
  }

  @override
  Stream<UpdaterEvent> get events {
    final existing = _translator;
    if (existing != null) return existing.events;
    final translator = _UpdaterEventTranslator();
    autoUpdater.addListener(translator);
    _translator = translator;
    return translator.events;
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

/// Internal adapter that implements the plugin's `UpdaterListener` and
/// forwards each callback as a sealed [UpdaterEvent] through a broadcast
/// stream. Kept private to the orchestrator file so the only public
/// surface remains [IAutoUpdaterGateway.events].
class _UpdaterEventTranslator with UpdaterListener {
  final StreamController<UpdaterEvent> _controller = StreamController<UpdaterEvent>.broadcast();

  Stream<UpdaterEvent> get events => _controller.stream;

  @override
  void onUpdaterError(UpdaterError? error) {
    _controller.add(UpdaterErrorEvent(message: error?.toString()));
  }

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    _controller.add(UpdaterCheckingForUpdate(itemCount: appcast?.items.length));
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    _controller.add(
      UpdaterUpdateAvailable(
        version: appcastItem?.versionString,
        displayVersion: appcastItem?.displayVersionString,
      ),
    );
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    _controller.add(UpdaterUpdateNotAvailable(errorMessage: error?.message));
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    _controller.add(UpdaterUpdateDownloaded(version: appcastItem?.versionString));
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    _controller.add(UpdaterBeforeQuitForUpdate(version: appcastItem?.versionString));
  }
}

/// Orchestrates WinSparkle (manual/background) and the silent update path.
///
/// The silent update cycle (probe → download → helper) is fully delegated to
/// [SilentUpdateCoordinator]. This class owns the WinSparkle event handling,
/// the manual check flow, the circuit-breaker for timeouts, and the overall
/// lifecycle (initialize, startAutomaticChecks, setAutomaticSilentUpdatesEnabled).
///
/// The orchestrator consumes the sealed [UpdaterEvent] stream exposed by
/// [IAutoUpdaterGateway.events] instead of mixing the plugin's
/// `UpdaterListener` into its own type. Keeps the application layer free
/// of the platform-channel plugin types and lets [_handleUpdaterEvent]
/// dispatch with exhaustive pattern matching.
class AutoUpdateOrchestrator implements IAutoUpdateOrchestrator {
  /// Builds an orchestrator. The bulk of the timing knobs lives in
  /// [AutoUpdateOrchestratorOptions] (and [SilentUpdateCoordinatorOptions]
  /// for silent-path policies); the legacy per-field parameters are
  /// kept as overrides for callers that still pass individual values
  /// (mostly tests). Prefer the options bundle in new code.
  AutoUpdateOrchestrator(
    this._capabilities, {
    AutoUpdateOrchestratorOptions? options,
    SilentUpdateCoordinatorOptions? silentOptions,
    IAutoUpdaterGateway? updaterGateway,
    IAppcastProbeService appcastProbeService = const AppcastProbeService(),
    ISilentUpdateInstaller? silentUpdateInstaller,
    IAppSettingsStore? settingsStore,
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
       _appcastProbeService = appcastProbeService,
       _settingsStore = settingsStore,
       _metricsCollector = metricsCollector,
       _diagnosticsGateway = diagnosticsGateway,
       _allowQuitForUpdate = allowQuitForUpdate,
       _clock = clock ?? DateTime.now,
       _checkIdRecorder = checkIdRecorder ?? UpdateCheckIdRecorder(settingsStore: settingsStore),
       _manualTimeoutBreaker = PersistentCircuitBreaker(
         countKey: _timeoutConsecutiveCountKey,
         cooldownKey: _timeoutCooldownUntilKey,
         threshold: timeoutCircuitThreshold ?? options?.timeoutCircuitThreshold ?? 3,
         cooldown:
             timeoutCircuitCooldown ?? options?.timeoutCircuitCooldown ?? const Duration(minutes: 15),
         logName: 'auto_update_orchestrator',
         settingsStore: settingsStore,
         clock: clock,
       ) {
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
    _hydratePersistedDiagnostics();
  }

  /// Broadcasts state transitions (silent download finished, ready-to-apply,
  /// applying, error) so UI providers can subscribe without polling. Stays
  /// in pure-Dart territory (no Flutter import) so the application layer
  /// remains framework-agnostic per the architecture rules.
  final StreamController<void> _changesController = StreamController<void>.broadcast();

  void _notifyChanges() {
    if (_changesController.isClosed) return;
    _changesController.add(null);
  }

  /// Releases the resources the orchestrator owns: the updater event
  /// subscription and the in-memory `_changesController`. Safe to call
  /// from a DI teardown or from a test `tearDown`. Idempotent.
  Future<void> dispose() async {
    await _updaterEventsSubscription?.cancel();
    _updaterEventsSubscription = null;
    if (!_changesController.isClosed) {
      await _changesController.close();
    }
  }

  /// Merges legacy per-field parameters into an
  /// [AutoUpdateOrchestratorOptions] bundle. Lets the constructor
  /// accept either style without an awkward double-default sentinel.
  /// When [options] is provided, the per-field overrides take
  /// precedence (so a test can pass `options: ...` and still override
  /// just one knob).
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

  /// Best-effort push of [diagnostics] to the hub. The contract demands
  /// the gateway throttle, omit sensitive fields and swallow errors, so
  /// this method never awaits the future and never propagates exceptions
  /// (telemetry must not influence the auto-update flow).
  void _pushDiagnosticsBestEffort(
    UpdateCheckDiagnostics? diagnostics,
    AutoUpdateDiagnosticsSource source,
  ) {
    final gateway = _diagnosticsGateway;
    if (gateway == null || diagnostics == null) return;
    unawaited(
      Future<void>(() async {
        try {
          await gateway.push(diagnostics: diagnostics, source: source);
        } on Object catch (error, stackTrace) {
          developer.log(
            'Auto-update diagnostics push threw (ignored)',
            name: 'auto_update_orchestrator',
            level: 800,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }),
    );
  }

  final RuntimeCapabilities _capabilities;
  final AutoUpdateOrchestratorOptions _options;
  final SilentUpdateCoordinatorOptions _silentOptions;
  final IAutoUpdaterGateway _updaterGateway;
  final IAppcastProbeService _appcastProbeService;
  final IAppSettingsStore? _settingsStore;
  final IAutoUpdateMetricsCollector? _metricsCollector;
  final IAutoUpdateDiagnosticsGateway? _diagnosticsGateway;
  final Future<void> Function()? _allowQuitForUpdate;
  Duration get _manualTriggerTimeout => _options.manualTriggerTimeout;
  Duration get _manualCompletionTimeout => _options.manualCompletionTimeout;
  RetryPolicy get _backgroundRetry => _options.backgroundRetry;
  Duration get _lateCallbackDrainWindow => _options.lateCallbackDrainWindow;
  final DateTime Function() _clock;
  final UpdateCheckIdRecorder _checkIdRecorder;

  /// Shared circuit breaker that ladders consecutive manual-check
  /// timeouts into a cooldown window. Reused implementation lives in
  /// [PersistentCircuitBreaker].
  final PersistentCircuitBreaker _manualTimeoutBreaker;
  late final ISilentUpdateCoordinator _silentCoordinator;

  bool _isInitialized = false;

  /// Subscription to the gateway's sealed [UpdaterEvent] stream. Created
  /// on first [initialize] call so test paths that never initialise the
  /// orchestrator (e.g. degraded runtime) do not touch the underlying
  /// plugin's broadcast stream.
  StreamSubscription<UpdaterEvent>? _updaterEventsSubscription;
  Completer<Result<ManualCheckOutcome>>? _manualCheckCompleter;
  bool _isBackgroundCheckInProgress = false;
  UpdateCheckDiagnostics? _activeManualDiagnostics;
  UpdateCheckDiagnostics? _lastManualDiagnostics;
  UpdateCheckDiagnostics? _lastBackgroundDiagnostics;

  /// Derived flag — true whenever a manual check is in flight. We use
  /// `_activeCheckId` as the single source of truth: there is exactly
  /// one active manual cycle per non-null check id. The previous
  /// design carried a separate `_isManualCheck` boolean alongside the
  /// id, which created a dual source of truth and a real risk of the
  /// two going out of sync (e.g. `_isManualCheck=true` with
  /// `_activeCheckId=null` after a late callback).
  bool get _isManualCheck => _activeCheckId != null;
  String? _activeCheckId;
  DateTime? _lastManualCheckEndedAt;

  static const String _lastDiagnosticsKey = 'auto_update.last_manual_diagnostics';
  static const String _lastBackgroundDiagnosticsKey = 'auto_update.last_background_diagnostics';
  static const String _timeoutConsecutiveCountKey = 'auto_update.timeout_consecutive_count';
  static const String _timeoutCooldownUntilKey = 'auto_update.timeout_cooldown_until_ms';

  // Default values for the orchestrator's timing knobs live in
  // [AutoUpdateOrchestratorOptions]; the constructor now exposes the
  // bundle directly. The legacy per-field constructor parameters
  // continue to work as overrides for backward compatibility.

  String? get _feedUrl {
    final url = resolveAutoUpdateFeedUrl(environment: AppEnvironment.snapshot());
    if (url.isEmpty) return null;
    return isSparkleFeedUrl(url) ? url : null;
  }

  String _buildManualFeedUrl(String baseFeedUrl) {
    final uri = Uri.tryParse(baseFeedUrl);
    if (uri == null) return baseFeedUrl;
    final query = Map<String, String>.from(uri.queryParameters);
    query['cb'] = _clock().millisecondsSinceEpoch.toString();
    return uri.replace(queryParameters: query).toString();
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
  bool get updateNotificationsEnabled =>
      _settingsStore?.getBool(AppSettingsKeys.updateNotificationsEnabled) ?? true;

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

  Future<Result<ManualCheckOutcome>?> _buildCircuitOpenFailure(String feedUrl) async {
    final remaining = await _manualTimeoutBreaker.remainingCooldown();
    if (remaining == null) return null;
    final minutesRemaining = remaining.inMinutes;
    final humanRemaining = minutesRemaining >= 1 ? '$minutesRemaining min' : '${remaining.inSeconds}s';
    final now = _clock();
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

  /// Records a timeout occurrence and, when the threshold is reached,
  /// emits the circuit-opened metric. Delegates persistence to the
  /// shared [PersistentCircuitBreaker].
  Future<void> _recordTimeoutOutcome() async {
    final previousCount = _manualTimeoutBreaker.failureCount;
    final state = await _manualTimeoutBreaker.recordFailure();
    final justOpened = state.cooldownUntil != null &&
        previousCount + 1 >= _manualTimeoutBreaker.threshold &&
        previousCount < _manualTimeoutBreaker.threshold;
    if (justOpened) {
      _metricsCollector?.recordAutoUpdateCircuitOpened();
      _logManualCheck('Auto-update manual check circuit opened', checkId: _activeCheckId, level: 900);
    }
  }

  // ---------------------------------------------------------------------------
  // Metrics / diagnostics helpers
  // ---------------------------------------------------------------------------

  /// Routes a manual-path completion source to the corresponding
  /// counter on the metrics surface. Table-driven instead of a long
  /// switch so adding a new source means adding (or omitting) an entry
  /// here — no risk of forgetting a case and silently dropping a
  /// metric.
  ///
  /// Sources from the silent/automatic path are intentionally absent:
  /// the coordinator owns their counters directly. A lookup miss is a
  /// no-op (the source is not a manual metric).
  static final Map<UpdateCheckCompletionSource, void Function(IAutoUpdateMetricsCollector)>
      _manualCompletionMetricRouter =
      <UpdateCheckCompletionSource, void Function(IAutoUpdateMetricsCollector)>{
    UpdateCheckCompletionSource.updateAvailable: (m) => m.recordAutoUpdateManualCheckSuccessAvailable(),
    UpdateCheckCompletionSource.updateNotAvailable: (m) => m.recordAutoUpdateManualCheckSuccessNotAvailable(),
    UpdateCheckCompletionSource.updaterError: (m) => m.recordAutoUpdateManualCheckUpdaterError(),
    UpdateCheckCompletionSource.triggerTimeout: (m) => m.recordAutoUpdateManualCheckTriggerTimeout(),
    UpdateCheckCompletionSource.completionTimeout: (m) => m.recordAutoUpdateManualCheckCompletionTimeout(),
    UpdateCheckCompletionSource.triggerFailure: (m) => m.recordAutoUpdateManualCheckTriggerFailure(),
    UpdateCheckCompletionSource.notInitialized: (m) => m.recordAutoUpdateManualCheckNotInitialized(),
    UpdateCheckCompletionSource.circuitOpen: (m) => m.recordAutoUpdateCircuitOpenRejected(),
  };

  void _recordCompletionMetric(UpdateCheckCompletionSource source) {
    final metricsCollector = _metricsCollector;
    if (metricsCollector == null) return;
    _manualCompletionMetricRouter[source]?.call(metricsCollector);
  }

  UpdateCheckDiagnostics _buildBackgroundDiagnostics(String feedUrl) {
    final now = _clock();
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
          checkedAt: _clock(),
          configuredFeedUrl: feedUrl,
          requestedFeedUrl: feedUrl,
          currentVersion: AppConstants.appVersion,
        );
  }

  int _resolveWinSparkleIntervalSeconds() {
    if (automaticSilentUpdatesEnabled) return 0;
    if (!updateNotificationsEnabled) return 0;
    return resolveAutoUpdateCheckIntervalSeconds(environment: AppEnvironment.snapshot());
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
        await _updaterGateway.setScheduledCheckInterval(_resolveWinSparkleIntervalSeconds());
      }
      if (!enabled) {
        // Signal in-flight check (if any) to bail out at the next safe
        // checkpoint before tearing down the periodic timer; cancellation is
        // a no-op when no check is running.
        _silentCoordinator.requestCancellation();
        _silentCoordinator.stop();
        _metricsCollector?.recordAutoUpdateAutomaticSilentPreferenceDisabled();
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
    final settingsStore = _settingsStore;
    if (settingsStore == null) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Settings store is not available',
          context: <String, dynamic>{'operation': 'setUpdateNotificationsEnabled'},
        ),
      );
    }
    try {
      await settingsStore.setBool(AppSettingsKeys.updateNotificationsEnabled, enabled);
      if (_isInitialized) {
        await _updaterGateway.setScheduledCheckInterval(_resolveWinSparkleIntervalSeconds());
      }
      if (enabled) {
        _metricsCollector?.recordAutoUpdateNotificationsPreferenceEnabled();
      } else {
        _metricsCollector?.recordAutoUpdateNotificationsPreferenceDisabled();
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
    _metricsCollector?.recordAutoUpdateManualOnlyModeApplied();
    return const Success(unit);
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

  // ---------------------------------------------------------------------------
  // Update checks
  // ---------------------------------------------------------------------------

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
    // Pause the periodic timer so a coincident automatic tick does not
    // collide with the user-initiated check. Without this guard the
    // coordinator would return `alreadyInProgress` and the operator
    // would see a confusing "could not prepare the installer" error.
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
      // Resume the periodic timer in all paths. On the success branch
      // the helper will shortly close the app, but a flake there must
      // not leave the coordinator permanently stopped. We deliberately
      // skip the immediate kick-off: a brand-new probe right after a
      // user-initiated apply would race the shutdown handler that the
      // helper is about to trigger.
      if (shouldResumeTimer) {
        _silentCoordinator.scheduleAndStart(runImmediately: false);
      }
    }
  }

  // The outcome → typed failure mapping moved to
  // `UserInitiatedApplyFailure.fromOutcome` in
  // `user_initiated_apply_failure.dart`. The banner now switches on the
  // sealed subtype instead of probing `context['outcome']` strings.

  @override
  Future<void> checkInBackground() async {
    if (!isAvailable) return;
    if (automaticSilentUpdatesEnabled) {
      await _silentCoordinator.checkSilently();
      return;
    }
    if (!updateNotificationsEnabled) {
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
    // The plugin's callbacks do not carry a correlation id, so a
    // background trigger fired while a manual cycle is in flight would
    // have its responses misclassified by `_isManualCheck`. Skip the
    // background tick instead — the periodic timer will fire again on
    // the next interval.
    if (_isManualCheck) {
      developer.log(
        'Background update check skipped: a manual check is already in flight (check_id=$_activeCheckId)',
        name: 'auto_update_orchestrator',
        level: 800,
      );
      return;
    }
    final feedUrl = _feedUrl;
    if (feedUrl == null) return;
    _isBackgroundCheckInProgress = true;
    try {
      for (var attempt = 1; attempt <= _backgroundRetry.attemptLimit; attempt++) {
        _lastBackgroundDiagnostics = _buildBackgroundDiagnostics(feedUrl);
        try {
          // Bounded trigger: without a timeout an unresponsive updater process
          // would leave the await suspended indefinitely, blocking the retry
          // loop and any future cycles (until the app restarts).
          await _updaterGateway.checkForUpdates(inBackground: true).timeout(_backgroundRetry.triggerTimeout);
          _lastBackgroundDiagnostics = _lastBackgroundDiagnostics?.copyWith(
            triggerCompletedAt: _clock(),
          );
          unawaited(_persistLastBackgroundDiagnostics());
          _pushDiagnosticsBestEffort(_lastBackgroundDiagnostics, AutoUpdateDiagnosticsSource.background);
          return;
        } on Exception catch (e, s) {
          final completedAt = _clock();
          _lastBackgroundDiagnostics = _lastBackgroundDiagnostics?.copyWith(
            triggerCompletedAt: completedAt,
            completedAt: completedAt,
            completionSource: UpdateCheckCompletionSource.triggerFailure,
            errorMessage: e.toString(),
          );
          _metricsCollector?.recordAutoUpdateBackgroundCheckTriggerFailure();
          unawaited(_persistLastBackgroundDiagnostics());
          _pushDiagnosticsBestEffort(_lastBackgroundDiagnostics, AutoUpdateDiagnosticsSource.background);
          developer.log(
            'Background update check failed (attempt $attempt/${_backgroundRetry.attemptLimit})',
            name: 'auto_update_orchestrator',
            level: 900,
            error: e,
            stackTrace: s,
          );
          if (attempt < _backgroundRetry.attemptLimit) {
            final delay = _backgroundRetry.delayBeforeAttempt(attempt);
            developer.log(
              'Retrying in ${delay.inMilliseconds}ms',
              name: 'auto_update_orchestrator',
              level: 800,
            );
            await Future<void>.delayed(delay);
            // Bail out of the retry loop when the runtime state turned
            // hostile during the sleep: the user disabled auto-update,
            // the feed URL changed to something incompatible, or the
            // silent path took over. Without this check we would wake
            // up and dispatch one extra `checkForUpdates` against an
            // updater that no longer makes sense to drive.
            if (!isAvailable || automaticSilentUpdatesEnabled || !updateNotificationsEnabled) {
              developer.log(
                'Background update retry aborted after delay: '
                'isAvailable=$isAvailable, '
                'automaticSilentUpdatesEnabled=$automaticSilentUpdatesEnabled, '
                'updateNotificationsEnabled=$updateNotificationsEnabled',
                name: 'auto_update_orchestrator',
                level: 800,
              );
              return;
            }
          }
        }
      }
    } finally {
      _isBackgroundCheckInProgress = false;
    }
  }

  // _jitteredBackgroundRetryDelay moved to `RetryPolicy.delayBeforeAttempt`.

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
          checkedAt: _clock(),
          configuredFeedUrl: feedUrl,
          requestedFeedUrl: feedUrl,
          currentVersion: AppConstants.appVersion,
          completedAt: _clock(),
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
    // _activeCheckId is the canonical "manual in flight" marker; the
    // `_isManualCheck` getter derives from it so we never need to flip
    // a separate boolean out of sync.
    _activeCheckId = _checkIdRecorder.newId();
    unawaited(_checkIdRecorder.record(_activeCheckId!, source: 'manual'));
    final manualFeedUrl = _buildManualFeedUrl(feedUrl);
    _metricsCollector?.recordAutoUpdateManualCheckStarted();
    _activeManualDiagnostics = UpdateCheckDiagnostics(
      checkedAt: _clock(),
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
      final triggerStartedAt = _clock();
      _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
        triggerStartedAt: triggerStartedAt,
      );
      // Use WinSparkle check without UI so the Settings dialog is the only user-facing
      // result for "no update" / errors; native "up to date" duplicates Fluent feedback.
      await _updaterGateway.checkForUpdates(inBackground: true).timeout(_manualTriggerTimeout);
      final triggerCompletedAt = _clock();
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
      final now = _clock();
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
        await _manualTimeoutBreaker.reset();
      }
      await _persistLastManualDiagnostics();
      _pushDiagnosticsBestEffort(_lastManualDiagnostics, AutoUpdateDiagnosticsSource.manual);
      _activeManualDiagnostics = null;
      // Clearing `_activeCheckId` is what flips `_isManualCheck` back
      // to false (single source of truth, see field declaration).
      _manualCheckCompleter = null;
      _activeCheckId = null;
      _lastManualCheckEndedAt = _clock();
    }
  }

  /// True when a callback from WinSparkle arrived after `checkManual` already
  /// ended (typically via [_manualCompletionTimeout]) and within
  /// [_lateCallbackDrainWindow]. These callbacks must not be persisted as
  /// background diagnostics or count as background failures. Uses the
  /// injected [_clock] so an NTP step on the host machine cannot
  /// misclassify the window — tests can also drive it deterministically.
  bool _isLateManualCallback() {
    final lastEndedAt = _lastManualCheckEndedAt;
    if (lastEndedAt == null) return false;
    return _clock().difference(lastEndedAt) <= _lateCallbackDrainWindow;
  }

  void _completeManualCheck(
    Result<ManualCheckOutcome> result, {
    UpdateCheckCompletionSource? completionSource,
  }) {
    final completedAt = _clock();
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
          errorMessage: extractAutoUpdateFailureMessage(error),
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
  // WinSparkle event handling (sealed UpdaterEvent dispatcher)
  // ---------------------------------------------------------------------------

  /// Single entry point for every plugin notification, translated to the
  /// sealed [UpdaterEvent] tree by [AutoUpdaterGateway]. Pattern-matching
  /// keeps the dispatcher exhaustive: a new variant forces a new branch
  /// here, not a silent fall-through.
  void _handleUpdaterEvent(UpdaterEvent event) {
    switch (event) {
      case UpdaterErrorEvent():
        _onUpdaterError(event.message);
      case UpdaterCheckingForUpdate():
        _onUpdaterCheckingForUpdate(event.itemCount);
      case UpdaterUpdateAvailable():
        _onUpdaterUpdateAvailable(version: event.version, displayVersion: event.displayVersion);
      case UpdaterUpdateNotAvailable():
        _onUpdaterUpdateNotAvailable(errorMessage: event.errorMessage);
      case UpdaterUpdateDownloaded():
        _logManualCheck('Update downloaded: ${event.version}', checkId: _activeCheckId);
      case UpdaterBeforeQuitForUpdate():
        _onUpdaterBeforeQuitForUpdate(event.version);
    }
  }

  void _onUpdaterError(String? message) {
    if (!_isManualCheck) {
      if (_isLateManualCallback()) {
        developer.log(
          'Ignoring late auto-updater error from a previously timed-out manual check: $message',
          name: 'auto_update_orchestrator',
          level: 800,
        );
        return;
      }
      _lastBackgroundDiagnostics = _backgroundDiagnosticsOrDefault().copyWith(
        completedAt: _clock(),
        completionSource: UpdateCheckCompletionSource.updaterError,
        errorMessage: message ?? 'Update check failed',
      );
      _metricsCollector?.recordAutoUpdateBackgroundCheckUpdaterError();
      unawaited(_persistLastBackgroundDiagnostics());
      developer.log('Background auto-updater error: $message', name: 'auto_update_orchestrator', level: 900);
      return;
    }
    _logManualCheck('Auto-updater error: $message', checkId: _activeCheckId, level: 900);
    _completeManualCheck(
      Failure<ManualCheckOutcome, Exception>(
        _buildManualFailure(
          message: message ?? 'Update check failed',
          completionSource: UpdateCheckCompletionSource.updaterError,
          context: {'operation': 'onUpdaterError'},
        ),
      ),
      completionSource: UpdateCheckCompletionSource.updaterError,
    );
  }

  void _onUpdaterCheckingForUpdate(int? itemCount) {
    final items = itemCount ?? 0;
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
        triggerStartedAt: diagnostics.triggerStartedAt ?? _clock(),
      );
      unawaited(_persistLastBackgroundDiagnostics());
      developer.log(
        'Background check for updates... (items: $items)',
        name: 'auto_update_orchestrator',
        level: 800,
      );
      return;
    }
    _logManualCheck(
      'Checking for updates... (items: $items)',
      checkId: _activeCheckId,
    );
  }

  void _onUpdaterUpdateAvailable({String? version, String? displayVersion}) {
    if (!_isManualCheck) {
      if (_isLateManualCallback()) {
        developer.log(
          'Ignoring late update-available from a previously timed-out manual check: $version',
          name: 'auto_update_orchestrator',
          level: 800,
        );
        return;
      }
      _lastBackgroundDiagnostics = _backgroundDiagnosticsOrDefault().copyWith(
        completedAt: _clock(),
        completionSource: UpdateCheckCompletionSource.updateAvailable,
        updateAvailable: true,
        remoteVersion: version,
        remoteDisplayVersion: displayVersion,
      );
      unawaited(_persistLastBackgroundDiagnostics());
      developer.log(
        'Background update available: $version (display: $displayVersion)',
        name: 'auto_update_orchestrator',
        level: 800,
      );
      return;
    }
    _logManualCheck(
      'Update available: $version (display: $displayVersion)',
      checkId: _activeCheckId,
    );
    final probeVersion = _activeManualDiagnostics?.appcastProbeVersion;
    final probeMatchesSparkle = version != null && probeVersion != null ? version == probeVersion : null;
    if (probeMatchesSparkle == false) {
      _logManualCheck(
        'Probe version ($probeVersion) does not match Sparkle version ($version) '
        '— possible CDN cache skew',
        checkId: _activeCheckId,
        level: 900,
      );
    }
    _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
      remoteVersion: version,
      remoteDisplayVersion: displayVersion,
      probeMatchesSparkle: probeMatchesSparkle,
    );
    _completeManualCheck(
      const Success(ManualCheckOutcome.updateAvailable),
      completionSource: UpdateCheckCompletionSource.updateAvailable,
    );
  }

  void _onUpdaterUpdateNotAvailable({String? errorMessage}) {
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
        completedAt: _clock(),
        completionSource: UpdateCheckCompletionSource.updateNotAvailable,
        updateAvailable: false,
        errorMessage: errorMessage,
      );
      unawaited(_persistLastBackgroundDiagnostics());
      developer.log(
        'No background update available (error: $errorMessage)',
        name: 'auto_update_orchestrator',
        level: 800,
      );
      return;
    }
    _logManualCheck(
      'No update available (manual: $_isManualCheck, error: $errorMessage)',
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
    if (errorMessage != null) {
      _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(errorMessage: errorMessage);
    }
    _completeManualCheck(
      const Success(ManualCheckOutcome.noUpdate),
      completionSource: UpdateCheckCompletionSource.updateNotAvailable,
    );
  }

  void _onUpdaterBeforeQuitForUpdate(String? version) {
    _logManualCheck(
      'Before quit for update: $version',
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
