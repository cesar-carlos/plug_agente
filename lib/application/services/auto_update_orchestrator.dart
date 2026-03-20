import 'dart:async';
import 'dart:developer' as developer;

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
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
  }) : _updaterGateway = updaterGateway,
       _appcastProbeService = appcastProbeService;

  final RuntimeCapabilities _capabilities;
  final IAutoUpdaterGateway _updaterGateway;
  final IAppcastProbeService _appcastProbeService;

  bool _isInitialized = false;
  Completer<Result<bool>>? _manualCheckCompleter;
  bool _isManualCheck = false;
  UpdateCheckDiagnostics? _activeManualDiagnostics;
  UpdateCheckDiagnostics? _lastManualDiagnostics;

  String? get _feedUrl {
    final url = resolveAutoUpdateFeedUrl(environment: dotenv.env);
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

  @override
  bool get isAvailable => _capabilities.supportsAutoUpdate && _feedUrl != null;

  @override
  UpdateCheckDiagnostics? get lastManualDiagnostics => _lastManualDiagnostics;

  @override
  Future<void> initialize() async {
    final feedUrl = _feedUrl;
    if (feedUrl == null) {
      developer.log(
        'Auto-update skipped: AUTO_UPDATE_FEED_URL not configured or not a Sparkle feed',
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
      environment: dotenv.env,
    );

    try {
      _updaterGateway.addListener(this);
      await _updaterGateway.setFeedURL(feedUrl);
      await _updaterGateway.setScheduledCheckInterval(intervalSeconds);
      _isInitialized = true;
      developer.log(
        'Auto-update initialized (feed: $feedUrl, interval: ${intervalSeconds}s)',
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

  static const int _maxBackgroundRetries = 3;
  static const Duration _retryBaseDelay = Duration(seconds: 30);

  @override
  Future<void> checkInBackground() async {
    if (!isAvailable) return;
    for (var attempt = 1; attempt <= _maxBackgroundRetries; attempt++) {
      try {
        await _updaterGateway.checkForUpdates(inBackground: true);
        return;
      } on Exception catch (e, s) {
        developer.log(
          'Background update check failed (attempt $attempt/$_maxBackgroundRetries)',
          name: 'auto_update_orchestrator',
          level: 900,
          error: e,
          stackTrace: s,
        );
        if (attempt < _maxBackgroundRetries) {
          final delay = _retryBaseDelay * attempt;
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

  static const Duration _manualCheckTimeout = Duration(seconds: 60);

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

    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized) {
        return Failure<bool, Exception>(
          domain.ServerFailure.withContext(
            message: 'Auto-update is not initialized',
            context: {'operation': 'checkManual'},
          ),
        );
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
    final manualFeedUrl = _buildManualFeedUrl(feedUrl);
    _activeManualDiagnostics = UpdateCheckDiagnostics(
      checkedAt: DateTime.now(),
      configuredFeedUrl: feedUrl,
      requestedFeedUrl: manualFeedUrl,
    );
    try {
      developer.log(
        'Manual update check triggered (configured feed: $feedUrl, requested feed: $manualFeedUrl)',
        name: 'auto_update_orchestrator',
        level: 800,
      );
      final probeResult = await _appcastProbeService.probeLatest(
        feedUrl: manualFeedUrl,
      );
      _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
        appcastProbeVersion: probeResult.latestVersion,
        appcastProbeItemCount: probeResult.itemCount,
        probeErrorMessage: probeResult.errorMessage,
      );
      await _updaterGateway.setFeedURL(manualFeedUrl);
      await _updaterGateway.checkForUpdates(inBackground: false);
      return await _manualCheckCompleter!.future.timeout(
        _manualCheckTimeout,
        onTimeout: () {
          _completeManualCheck(
            Failure<bool, Exception>(
              domain.ServerFailure.withContext(
                message: 'Update check timed out',
                context: {'operation': 'checkManual'},
              ),
            ),
          );
          return _manualCheckCompleter!.future;
        },
      );
    } on Exception catch (e) {
      final failure = Failure<bool, Exception>(
        domain.ServerFailure.withContext(
          message: 'Failed to trigger update check',
          cause: e,
          context: {'operation': 'checkManual'},
        ),
      );
      _completeManualCheck(failure);
      return failure;
    } finally {
      _lastManualDiagnostics = _activeManualDiagnostics;
      _activeManualDiagnostics = null;
      _isManualCheck = false;
      _manualCheckCompleter = null;
    }
  }

  void _completeManualCheck(Result<bool> result) {
    result.fold(
      (isUpdateAvailable) {
        _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
          updateAvailable: isUpdateAvailable,
        );
      },
      (error) {
        _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
          errorMessage: _extractFailureMessage(error),
        );
      },
    );
    if (_isManualCheck && _manualCheckCompleter != null && !_manualCheckCompleter!.isCompleted) {
      _manualCheckCompleter!.complete(result);
    }
  }

  @override
  void onUpdaterError(UpdaterError? error) {
    developer.log(
      'Auto-updater error: $error',
      name: 'auto_update_orchestrator',
      level: 900,
    );
    _completeManualCheck(
      Failure<bool, Exception>(
        domain.ServerFailure.withContext(
          message: error?.toString() ?? 'Update check failed',
          context: {'operation': 'onUpdaterError'},
        ),
      ),
    );
  }

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    developer.log(
      'Checking for updates... (items: ${appcast?.items.length ?? 0})',
      name: 'auto_update_orchestrator',
      level: 800,
    );
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    developer.log(
      'Update available: ${appcastItem?.versionString} (display: ${appcastItem?.displayVersionString})',
      name: 'auto_update_orchestrator',
      level: 800,
    );
    _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
      remoteVersion: appcastItem?.versionString,
      remoteDisplayVersion: appcastItem?.displayVersionString,
    );
    _completeManualCheck(const Success(true));
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    developer.log(
      'No update available (manual: $_isManualCheck, error: $error)',
      name: 'auto_update_orchestrator',
      level: 800,
    );
    if (error != null) {
      _activeManualDiagnostics = _activeManualDiagnostics?.copyWith(
        errorMessage: error.message,
      );
    }
    _completeManualCheck(const Success(false));
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    developer.log(
      'Update downloaded: ${appcastItem?.versionString}',
      name: 'auto_update_orchestrator',
      level: 800,
    );
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    developer.log(
      'Before quit for update: ${appcastItem?.versionString}',
      name: 'auto_update_orchestrator',
      level: 800,
    );
    windowManager.setPreventClose(false);
  }
}
