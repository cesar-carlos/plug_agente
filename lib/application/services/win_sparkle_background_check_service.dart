import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:plug_agente/application/observability/i_auto_update_diagnostics_gateway.dart';
import 'package:plug_agente/application/observability/i_auto_update_metrics_collector.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/observability/update_check_id_recorder.dart';
import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator_options.dart';
import 'package:plug_agente/application/services/auto_updater_gateway.dart';
import 'package:plug_agente/application/services/retry_policy.dart';
import 'package:plug_agente/application/services/win_sparkle_manual_check_service.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';

/// WinSparkle background update check with bounded retry loop.
class WinSparkleBackgroundCheckService {
  WinSparkleBackgroundCheckService({
    required IAutoUpdaterGateway updaterGateway,
    required IUpdatePreferencesRepository preferences,
    required WinSparkleManualCheckService manualCheckService,
    required AutoUpdateOrchestratorOptions options,
    IAutoUpdateMetricsCollector? metricsCollector,
    IAutoUpdateDiagnosticsGateway? diagnosticsGateway,
    UpdateCheckIdRecorder? checkIdRecorder,
    DateTime Function()? clock,
    String? Function()? feedUrlResolver,
    void Function()? onDiagnosticsChanged,
  }) : _updaterGateway = updaterGateway,
       _preferences = preferences,
       _manualCheckService = manualCheckService,
       _backgroundRetry = options.backgroundRetry,
       _metricsCollector = metricsCollector,
       _diagnosticsGateway = diagnosticsGateway,
       _checkIdRecorder = checkIdRecorder ?? UpdateCheckIdRecorder(),
       _clock = clock ?? DateTime.now,
       _feedUrlResolver = feedUrlResolver,
       _onDiagnosticsChanged = onDiagnosticsChanged {
    _hydratePersistedDiagnostics();
  }

  final IAutoUpdaterGateway _updaterGateway;
  final IUpdatePreferencesRepository _preferences;
  final WinSparkleManualCheckService _manualCheckService;
  final RetryPolicy _backgroundRetry;
  final IAutoUpdateMetricsCollector? _metricsCollector;
  final IAutoUpdateDiagnosticsGateway? _diagnosticsGateway;
  final UpdateCheckIdRecorder _checkIdRecorder;
  final DateTime Function() _clock;
  final String? Function()? _feedUrlResolver;
  final void Function()? _onDiagnosticsChanged;

  bool _isBackgroundCheckInProgress = false;
  UpdateCheckDiagnostics? _lastBackgroundDiagnostics;

  UpdateCheckDiagnostics? get lastBackgroundDiagnostics => _lastBackgroundDiagnostics;

  void _hydratePersistedDiagnostics() {
    final raw = _preferences.readLastBackgroundDiagnosticsJson();
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _lastBackgroundDiagnostics = UpdateCheckDiagnostics.fromJson(decoded);
      }
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Failed to parse persisted background auto-update diagnostics',
        name: 'win_sparkle_background_check_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _pushDiagnosticsBestEffort(UpdateCheckDiagnostics? diagnostics) {
    final gateway = _diagnosticsGateway;
    if (gateway == null || diagnostics == null) return;
    unawaited(
      Future<void>(() async {
        try {
          await gateway.push(diagnostics: diagnostics, source: AutoUpdateDiagnosticsSource.background);
        } on Object catch (error, stackTrace) {
          developer.log(
            'Auto-update diagnostics push threw (ignored)',
            name: 'win_sparkle_background_check_service',
            level: 800,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }),
    );
  }

  Future<void> _persistLastBackgroundDiagnostics() async {
    final diagnostics = _lastBackgroundDiagnostics;
    if (diagnostics == null) return;
    try {
      await _preferences.writeLastBackgroundDiagnosticsJson(jsonEncode(diagnostics.toJson()));
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to persist background auto-update diagnostics',
        name: 'win_sparkle_background_check_service',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _persistLastBackgroundDiagnosticsAndNotify() {
    unawaited(() async {
      await _persistLastBackgroundDiagnostics();
      _onDiagnosticsChanged?.call();
    }());
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
    final feedUrl = _feedUrlResolver?.call() ?? officialAutoUpdateFeedUrl;
    return _lastBackgroundDiagnostics ??
        UpdateCheckDiagnostics(
          checkedAt: _clock(),
          configuredFeedUrl: feedUrl,
          requestedFeedUrl: feedUrl,
          currentVersion: AppConstants.appVersion,
        );
  }

  Future<void> checkInBackground({
    required bool isAvailable,
    required bool automaticSilentUpdatesEnabled,
    required String? feedUrl,
  }) async {
    if (!isAvailable) return;
    if (automaticSilentUpdatesEnabled) return;
    if (!_preferences.updateNotificationsEnabled) return;
    if (_isBackgroundCheckInProgress) {
      developer.log(
        'Background update check skipped: another background check is already running',
        name: 'win_sparkle_background_check_service',
        level: 800,
      );
      return;
    }
    if (_manualCheckService.isManualCheckInProgress) {
      developer.log(
        'Background update check skipped: a manual check is already in flight',
        name: 'win_sparkle_background_check_service',
        level: 800,
      );
      return;
    }
    if (feedUrl == null) return;
    _isBackgroundCheckInProgress = true;
    try {
      for (var attempt = 1; attempt <= _backgroundRetry.attemptLimit; attempt++) {
        _lastBackgroundDiagnostics = _buildBackgroundDiagnostics(feedUrl);
        try {
          await _updaterGateway.checkForUpdates(inBackground: true).timeout(_backgroundRetry.triggerTimeout);
          _lastBackgroundDiagnostics = _lastBackgroundDiagnostics?.copyWith(
            triggerCompletedAt: _clock(),
          );
          unawaited(_persistLastBackgroundDiagnostics());
          _pushDiagnosticsBestEffort(_lastBackgroundDiagnostics);
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
          _pushDiagnosticsBestEffort(_lastBackgroundDiagnostics);
          developer.log(
            'Background update check failed (attempt $attempt/${_backgroundRetry.attemptLimit})',
            name: 'win_sparkle_background_check_service',
            level: 900,
            error: e,
            stackTrace: s,
          );
          if (attempt < _backgroundRetry.attemptLimit) {
            final delay = _backgroundRetry.delayBeforeAttempt(attempt);
            developer.log(
              'Retrying in ${delay.inMilliseconds}ms',
              name: 'win_sparkle_background_check_service',
              level: 800,
            );
            await Future<void>.delayed(delay);
            if (!isAvailable ||
                automaticSilentUpdatesEnabled ||
                !_preferences.updateNotificationsEnabled) {
              developer.log(
                'Background update retry aborted after delay: '
                'isAvailable=$isAvailable, '
                'automaticSilentUpdatesEnabled=$automaticSilentUpdatesEnabled, '
                'updateNotificationsEnabled=${_preferences.updateNotificationsEnabled}',
                name: 'win_sparkle_background_check_service',
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

  void onUpdaterError(String? message) {
    if (_manualCheckService.isLateManualCallback()) {
      developer.log(
        'Ignoring late auto-updater error from a previously timed-out manual check: $message',
        name: 'win_sparkle_background_check_service',
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
    _persistLastBackgroundDiagnosticsAndNotify();
    developer.log('Background auto-updater error: $message', name: 'win_sparkle_background_check_service', level: 900);
  }

  void onUpdaterCheckingForUpdate(int? itemCount) {
    if (_manualCheckService.isLateManualCallback()) {
      developer.log(
        'Ignoring late checking-for-update from a previously timed-out manual check',
        name: 'win_sparkle_background_check_service',
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
      'Background check for updates... (items: ${itemCount ?? 0})',
      name: 'win_sparkle_background_check_service',
      level: 800,
    );
  }

  void onUpdaterUpdateAvailable({String? version, String? displayVersion}) {
    if (_manualCheckService.isLateManualCallback()) {
      developer.log(
        'Ignoring late update-available from a previously timed-out manual check: $version',
        name: 'win_sparkle_background_check_service',
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
    _persistLastBackgroundDiagnosticsAndNotify();
    developer.log(
      'Background update available: $version (display: $displayVersion)',
      name: 'win_sparkle_background_check_service',
      level: 800,
    );
  }

  void onUpdaterUpdateNotAvailable({String? errorMessage}) {
    if (_manualCheckService.isLateManualCallback()) {
      developer.log(
        'Ignoring late update-not-available from a previously timed-out manual check',
        name: 'win_sparkle_background_check_service',
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
    _persistLastBackgroundDiagnosticsAndNotify();
    developer.log(
      'No background update available (error: $errorMessage)',
      name: 'win_sparkle_background_check_service',
      level: 800,
    );
  }
}
