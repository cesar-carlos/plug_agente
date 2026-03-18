import 'dart:async';
import 'dart:developer' as developer;

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';
import 'package:window_manager/window_manager.dart';

class AutoUpdateOrchestrator with UpdaterListener implements IAutoUpdateOrchestrator {
  AutoUpdateOrchestrator();

  static const int _scheduledCheckIntervalSeconds = 3600;

  bool _isInitialized = false;
  Completer<Result<bool>>? _manualCheckCompleter;
  bool _isManualCheck = false;

  bool _isSparkleFeedUrl(String url) {
    final normalized = url.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final withoutQuery = normalized.split('?').first;
    return withoutQuery.endsWith('.xml');
  }

  String? get _feedUrl {
    final url = dotenv.env['AUTO_UPDATE_FEED_URL']?.trim();
    if (url == null || url.isEmpty) return null;
    return _isSparkleFeedUrl(url) ? url : null;
  }

  @override
  bool get isAvailable => _feedUrl != null;

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

    try {
      autoUpdater.addListener(this);
      await autoUpdater.setFeedURL(feedUrl);
      await autoUpdater.setScheduledCheckInterval(_scheduledCheckIntervalSeconds);
      _isInitialized = true;
      developer.log(
        'Auto-update initialized (feed: $feedUrl, interval: ${_scheduledCheckIntervalSeconds}s)',
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
  Future<void> checkInBackground() async {
    if (!isAvailable) return;
    try {
      await autoUpdater.checkForUpdates(inBackground: true);
    } on Exception catch (e, s) {
      developer.log(
        'Background update check failed',
        name: 'auto_update_orchestrator',
        level: 900,
        error: e,
        stackTrace: s,
      );
    }
  }

  static const Duration _manualCheckTimeout = Duration(seconds: 60);

  @override
  Future<Result<bool>> checkManual() async {
    final feedUrl = _feedUrl;
    if (feedUrl == null) {
      return Failure<bool, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Update feed URL is not configured',
          context: {'operation': 'checkManual'},
        ),
      );
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
    try {
      await autoUpdater.checkForUpdates(inBackground: true);
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
      _isManualCheck = false;
      _manualCheckCompleter = null;
    }
  }

  void _completeManualCheck(Result<bool> result) {
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
      'Checking for updates...',
      name: 'auto_update_orchestrator',
      level: 800,
    );
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    developer.log(
      'Update available: ${appcastItem?.versionString}',
      name: 'auto_update_orchestrator',
      level: 800,
    );
    _completeManualCheck(const Success(true));
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    developer.log(
      'No update available',
      name: 'auto_update_orchestrator',
      level: 800,
    );
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
