import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:plug_agente/application/observability/i_auto_update_diagnostics_gateway.dart';
import 'package:plug_agente/application/observability/i_auto_update_metrics_collector.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/observability/update_check_id_recorder.dart';
import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/auto_update_failure_messages.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator_options.dart';
import 'package:plug_agente/application/services/auto_updater_gateway.dart';
import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// WinSparkle manual update check flow with timeout circuit breaker.
class WinSparkleManualCheckService {
  WinSparkleManualCheckService({
    required RuntimeCapabilities capabilities,
    required IAutoUpdaterGateway updaterGateway,
    required IAppcastProbeService appcastProbeService,
    required IUpdatePreferencesRepository preferences,
    required AutoUpdateOrchestratorOptions options,
    IAutoUpdateMetricsCollector? metricsCollector,
    IAutoUpdateDiagnosticsGateway? diagnosticsGateway,
    UpdateCheckIdRecorder? checkIdRecorder,
    PersistentCircuitBreaker? manualTimeoutBreaker,
    DateTime Function()? clock,
  }) : _capabilities = capabilities,
       _updaterGateway = updaterGateway,
       _appcastProbeService = appcastProbeService,
       _preferences = preferences,
       _options = options,
       _metricsCollector = metricsCollector,
       _diagnosticsGateway = diagnosticsGateway,
       _checkIdRecorder = checkIdRecorder ?? UpdateCheckIdRecorder(),
       _manualTimeoutBreaker =
           manualTimeoutBreaker ??
           PersistentCircuitBreaker(
             persistence: preferences.manualTimeoutCircuitPersistence(),
             threshold: options.timeoutCircuitThreshold,
             cooldown: options.timeoutCircuitCooldown,
             logName: 'win_sparkle_manual_check_service',
             clock: clock,
           ),
       _clock = clock ?? DateTime.now {
    _hydratePersistedDiagnostics();
  }

  final RuntimeCapabilities _capabilities;
  final IAutoUpdaterGateway _updaterGateway;
  final IAppcastProbeService _appcastProbeService;
  final IUpdatePreferencesRepository _preferences;
  final AutoUpdateOrchestratorOptions _options;
  final IAutoUpdateMetricsCollector? _metricsCollector;
  final IAutoUpdateDiagnosticsGateway? _diagnosticsGateway;
  final UpdateCheckIdRecorder _checkIdRecorder;
  final PersistentCircuitBreaker _manualTimeoutBreaker;
  final DateTime Function() _clock;

  Duration get _manualTriggerTimeout => _options.manualTriggerTimeout;
  Duration get _manualCompletionTimeout => _options.manualCompletionTimeout;
  Duration get _lateCallbackDrainWindow => _options.lateCallbackDrainWindow;

  Completer<Result<ManualCheckOutcome>>? _manualCheckCompleter;
  UpdateCheckDiagnostics? _activeManualDiagnostics;
  UpdateCheckDiagnostics? _lastManualDiagnostics;
  String? _activeCheckId;
  DateTime? _lastManualCheckEndedAt;

  bool get isManualCheckInProgress => _activeCheckId != null;
  UpdateCheckDiagnostics? get lastManualDiagnostics => _lastManualDiagnostics;
  DateTime? get lastManualCheckEndedAt => _lastManualCheckEndedAt;

  void _hydratePersistedDiagnostics() {
    final raw = _preferences.readLastManualDiagnosticsJson();
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _lastManualDiagnostics = UpdateCheckDiagnostics.fromJson(decoded);
      }
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Failed to parse persisted auto-update diagnostics',
        name: 'win_sparkle_manual_check_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
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
      name: 'win_sparkle_manual_check_service',
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

  static final Map<UpdateCheckCompletionSource, void Function(IAutoUpdateMetricsCollector)>
  _manualCompletionMetricRouter = <UpdateCheckCompletionSource, void Function(IAutoUpdateMetricsCollector)>{
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

  void _pushDiagnosticsBestEffort(UpdateCheckDiagnostics? diagnostics) {
    final gateway = _diagnosticsGateway;
    if (gateway == null || diagnostics == null) return;
    unawaited(
      Future<void>(() async {
        try {
          await gateway.push(diagnostics: diagnostics, source: AutoUpdateDiagnosticsSource.manual);
        } on Object catch (error, stackTrace) {
          developer.log(
            'Auto-update diagnostics push threw (ignored)',
            name: 'win_sparkle_manual_check_service',
            level: 800,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }),
    );
  }

  Future<void> _persistLastManualDiagnostics() async {
    final diagnostics = _lastManualDiagnostics;
    if (diagnostics == null) return;
    try {
      await _preferences.writeLastManualDiagnosticsJson(jsonEncode(diagnostics.toJson()));
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to persist auto-update diagnostics',
        name: 'win_sparkle_manual_check_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

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

  Future<void> _recordTimeoutOutcome() async {
    final previousCount = _manualTimeoutBreaker.failureCount;
    final state = await _manualTimeoutBreaker.recordFailure();
    final justOpened =
        state.cooldownUntil != null &&
        previousCount + 1 >= _manualTimeoutBreaker.threshold &&
        previousCount < _manualTimeoutBreaker.threshold;
    if (justOpened) {
      _metricsCollector?.recordAutoUpdateCircuitOpened();
      _logManualCheck('Auto-update manual check circuit opened', checkId: _activeCheckId, level: 900);
    }
  }

  bool isLateManualCallback() {
    final lastEndedAt = _lastManualCheckEndedAt;
    if (lastEndedAt == null) return false;
    return _clock().difference(lastEndedAt) <= _lateCallbackDrainWindow;
  }

  Future<Result<ManualCheckOutcome>> checkManual({
    required String? feedUrl,
    required bool Function() isInitialized,
    required Future<void> Function() ensureInitialized,
  }) async {
    if (!_capabilities.supportsAutoUpdate) {
      return Failure<ManualCheckOutcome, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Auto-update is not supported in current runtime mode',
          context: {'operation': 'checkManual'},
        ),
      );
    }
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

    if (!isInitialized()) {
      await ensureInitialized();
      if (!isInitialized()) {
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
    if (isManualCheckInProgress) {
      return Failure<ManualCheckOutcome, Exception>(
        domain.ServerFailure.withContext(
          message: 'Update check already in progress',
          context: {'operation': 'checkManual'},
        ),
      );
    }
    _manualCheckCompleter = Completer<Result<ManualCheckOutcome>>();
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
      _pushDiagnosticsBestEffort(_lastManualDiagnostics);
      _activeManualDiagnostics = null;
      _manualCheckCompleter = null;
      _activeCheckId = null;
      _lastManualCheckEndedAt = _clock();
    }
  }

  void onUpdaterError(String? message) {
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

  void onUpdaterCheckingForUpdate(int? itemCount) {
    final items = itemCount ?? 0;
    _logManualCheck(
      'Checking for updates... (items: $items)',
      checkId: _activeCheckId,
    );
  }

  void onUpdaterUpdateAvailable({String? version, String? displayVersion}) {
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

  void onUpdaterUpdateNotAvailable({String? errorMessage}) {
    _logManualCheck(
      'No update available (manual: $isManualCheckInProgress, error: $errorMessage)',
      checkId: _activeCheckId,
    );
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
    if (isManualCheckInProgress && _manualCheckCompleter != null && !_manualCheckCompleter!.isCompleted) {
      _manualCheckCompleter!.complete(result);
    }
  }
}
