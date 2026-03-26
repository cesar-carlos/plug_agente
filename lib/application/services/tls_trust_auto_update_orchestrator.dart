import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plug_agente/application/services/appcast_feed_parser.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/core/utils/app_version_compare.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// HTTPS appcast + version compare + browser download (TLS + GitHub host allowlist).
/// After [initialize], runs [checkInBackground] on a timer from
/// [resolveAutoUpdateCheckIntervalSeconds] when the feed is configured.
///
/// See `docs/install/auto_update_setup.md`.
class TlsTrustAutoUpdateOrchestrator implements IAutoUpdateOrchestrator {
  TlsTrustAutoUpdateOrchestrator(
    this._capabilities, {
    AppcastFeedParser feedParser = const AppcastFeedParser(),
    Duration fetchTimeout = const Duration(seconds: 20),
  }) : _feedParser = feedParser,
       _fetchTimeout = fetchTimeout;

  final RuntimeCapabilities _capabilities;
  final AppcastFeedParser _feedParser;
  final Duration _fetchTimeout;

  UpdateCheckDiagnostics? _lastManualDiagnostics;
  bool _initialized = false;
  Timer? _periodicBackgroundTimer;
  bool _backgroundCheckInProgress = false;

  String? get _feedUrl {
    final url = resolveAutoUpdateFeedUrl(environment: dotenv.env);
    if (url.isEmpty) {
      return null;
    }
    return isSparkleFeedUrl(url) ? url : null;
  }

  @override
  bool get isAvailable => _capabilities.supportsAutoUpdate && _feedUrl != null;

  @override
  UpdateCheckDiagnostics? get lastManualDiagnostics => _lastManualDiagnostics;

  @override
  Future<void> initialize() async {
    _initialized = true;
    developer.log(
      'HTTPS appcast auto-update initialized',
      name: 'tls_trust_auto_update',
      level: 800,
    );
    _periodicBackgroundTimer?.cancel();
    _periodicBackgroundTimer = null;
    if (!isAvailable) {
      return;
    }
    final intervalSeconds = resolveAutoUpdateCheckIntervalSeconds(
      environment: dotenv.env,
    );
    _periodicBackgroundTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) {
        unawaited(checkInBackground());
      },
    );
    developer.log(
      'Periodic appcast background check every ${intervalSeconds}s',
      name: 'tls_trust_auto_update',
      level: 800,
    );
  }

  @override
  Future<void> checkInBackground() async {
    if (!isAvailable) {
      return;
    }
    if (!_initialized) {
      await initialize();
    }
    final feedUrl = _feedUrl;
    if (feedUrl == null) {
      return;
    }
    if (_backgroundCheckInProgress) {
      return;
    }
    _backgroundCheckInProgress = true;
    try {
      try {
        final body = await _fetchUrl(feedUrl);
        final item = _feedParser.parseLatestWindowsItem(body);
        if (item == null) {
          return;
        }
        final pkg = await PackageInfo.fromPlatform();
        final current = _packageInfoToFullVersion(pkg);
        if (compareReleaseVersions(item.versionString, current) > 0) {
          developer.log(
            'TLS-trust background check: newer version ${item.versionString} '
            '(current $current). Open Settings to download.',
            name: 'tls_trust_auto_update',
            level: 800,
          );
        }
      } on Exception catch (e, s) {
        developer.log(
          'TLS-trust background check failed',
          name: 'tls_trust_auto_update',
          level: 900,
          error: e,
          stackTrace: s,
        );
      }
    } finally {
      _backgroundCheckInProgress = false;
    }
  }

  @override
  Future<Result<bool>> checkManual() async {
    if (!_capabilities.supportsAutoUpdate) {
      return Failure<bool, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Auto-update is not supported in current runtime mode',
          context: {'operation': 'checkManual', 'mode': 'tls_trust'},
        ),
      );
    }

    final feedUrl = _feedUrl;
    if (feedUrl == null) {
      return Failure<bool, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Update feed URL is not configured',
          context: {'operation': 'checkManual', 'mode': 'tls_trust'},
        ),
      );
    }

    if (!_initialized) {
      await initialize();
    }

    final manualFeedUrl = _cacheBustFeedUrl(feedUrl);
    final checkedAt = DateTime.now();

    try {
      final body = await _fetchUrl(manualFeedUrl);
      final item = _feedParser.parseLatestWindowsItem(body);
      if (item == null) {
        _lastManualDiagnostics = UpdateCheckDiagnostics(
          checkedAt: checkedAt,
          configuredFeedUrl: feedUrl,
          requestedFeedUrl: manualFeedUrl,
          errorMessage: 'No valid Windows enclosure in appcast.',
        );
        return Failure<bool, Exception>(
          domain.ServerFailure.withContext(
            message: 'Could not read update metadata from appcast',
            context: {'operation': 'checkManual', 'mode': 'tls_trust'},
          ),
        );
      }

      final downloadUri = Uri.parse(item.downloadUrl);
      if (!_isTrustedDownloadUri(downloadUri)) {
        _lastManualDiagnostics = UpdateCheckDiagnostics(
          checkedAt: checkedAt,
          configuredFeedUrl: feedUrl,
          requestedFeedUrl: manualFeedUrl,
          remoteVersion: item.versionString,
          errorMessage: 'Download URL host not allowed: ${downloadUri.host}',
        );
        return Failure<bool, Exception>(
          domain.ValidationFailure.withContext(
            message: 'Update download URL is not on an allowed host',
            context: {
              'operation': 'checkManual',
              'host': downloadUri.host,
            },
          ),
        );
      }

      final pkg = await PackageInfo.fromPlatform();
      final current = _packageInfoToFullVersion(pkg);
      final cmp = compareReleaseVersions(item.versionString, current);

      _lastManualDiagnostics = UpdateCheckDiagnostics(
        checkedAt: checkedAt,
        configuredFeedUrl: feedUrl,
        requestedFeedUrl: manualFeedUrl,
        appcastProbeVersion: item.versionString,
        appcastProbeItemCount: 1,
        updateAvailable: cmp > 0,
        remoteVersion: item.versionString,
      );

      if (cmp <= 0) {
        return const Success<bool, Exception>(false);
      }

      if (Platform.isWindows) {
        try {
          await _openDownloadInBrowser(item.downloadUrl);
        } on Object catch (e, s) {
          developer.log(
            'TLS-trust: failed to open download in browser',
            name: 'tls_trust_auto_update',
            level: 900,
            error: e,
            stackTrace: s,
          );
          _lastManualDiagnostics = UpdateCheckDiagnostics(
            checkedAt: checkedAt,
            configuredFeedUrl: feedUrl,
            requestedFeedUrl: manualFeedUrl,
            appcastProbeVersion: item.versionString,
            appcastProbeItemCount: 1,
            updateAvailable: true,
            remoteVersion: item.versionString,
            errorMessage: e.toString(),
          );
          return Failure<bool, Exception>(
            domain.ServerFailure.withContext(
              message: 'Could not open the download in your browser',
              cause: e,
              context: const {
                'operation': 'checkManual',
                'mode': 'tls_trust',
                'step': 'open_browser',
              },
            ),
          );
        }
      } else {
        developer.log(
          'TLS-trust: update available but skipping browser open (not Windows)',
          name: 'tls_trust_auto_update',
          level: 800,
        );
      }
      return const Success<bool, Exception>(true);
    } on Exception catch (e, s) {
      developer.log(
        'TLS-trust manual check failed',
        name: 'tls_trust_auto_update',
        level: 900,
        error: e,
        stackTrace: s,
      );
      _lastManualDiagnostics = UpdateCheckDiagnostics(
        checkedAt: checkedAt,
        configuredFeedUrl: feedUrl,
        requestedFeedUrl: manualFeedUrl,
        errorMessage: e.toString(),
      );
      return Failure<bool, Exception>(
        domain.NetworkFailure.withContext(
          message: 'Failed to check for updates',
          cause: e,
          context: {'operation': 'checkManual', 'mode': 'tls_trust'},
        ),
      );
    }
  }

  String _cacheBustFeedUrl(String baseFeedUrl) {
    final uri = Uri.tryParse(baseFeedUrl);
    if (uri == null) {
      return baseFeedUrl;
    }
    final query = Map<String, String>.from(
      uri.queryParameters,
    );
    query['cb'] = DateTime.now().millisecondsSinceEpoch.toString();
    return uri.replace(queryParameters: query).toString();
  }

  static String _packageInfoToFullVersion(PackageInfo pkg) {
    final build = pkg.buildNumber.trim();
    if (build.isEmpty) {
      return pkg.version.trim();
    }
    return '${pkg.version.trim()}+$build';
  }

  static bool _isTrustedDownloadUri(Uri uri) {
    if (uri.scheme != 'https') {
      return false;
    }
    final h = uri.host.toLowerCase();
    if (h == 'github.com') {
      return true;
    }
    if (h.endsWith('.github.com')) {
      return true;
    }
    if (h.endsWith('.githubusercontent.com')) {
      return true;
    }
    return false;
  }

  Future<String> _fetchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw const FormatException('Feed URL must be HTTPS');
    }

    final client = HttpClient();
    client.connectionTimeout = _fetchTimeout;
    try {
      final request = await client
          .getUrl(uri)
          .timeout(
            _fetchTimeout,
          );
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.headers.set(HttpHeaders.pragmaHeader, 'no-cache');
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/rss+xml,text/xml,*/*',
      );
      final response = await request.close().timeout(
        _fetchTimeout,
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _openDownloadInBrowser(String url) async {
    final result = await Process.run(
      'rundll32',
      <String>['url.dll,FileProtocolHandler', url],
    );
    if (result.exitCode != 0) {
      throw StateError(
        'rundll32 exit ${result.exitCode}: ${result.stderr}',
      );
    }
  }
}
