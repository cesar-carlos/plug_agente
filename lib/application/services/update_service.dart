import 'package:auto_updater/auto_updater.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class UpdateService {
  UpdateService(this._updateUrl, this._dio);
  final String _updateUrl;
  final Dio _dio;
  static const int _minimumScheduledCheckIntervalSeconds = 3600;

  Future<Result<bool>> checkForUpdates() async {
    if (_isSparkleFeedUrl(_updateUrl)) {
      return _checkForUpdatesViaSparkle();
    }
    return _checkForUpdatesViaApi();
  }

  bool _isSparkleFeedUrl(String url) {
    final normalized = url.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final withoutQuery = normalized.split('?').first;
    return withoutQuery.endsWith('.xml');
  }

  Future<Result<bool>> _checkForUpdatesViaSparkle() async {
    final feedUrl = _updateUrl.trim();
    if (feedUrl.isEmpty) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Update feed URL is not configured',
          context: {'operation': 'checkForUpdates'},
        ),
      );
    }

    try {
      await autoUpdater.setFeedURL(feedUrl);
      await autoUpdater.setScheduledCheckInterval(
        _minimumScheduledCheckIntervalSeconds,
      );
      await autoUpdater.checkForUpdates();
      return const Success(true);
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Failed to trigger update check',
          cause: error,
          context: {
            'operation': 'checkForUpdates',
            'feedUrl': feedUrl,
          },
        ),
      );
    }
  }

  Future<Result<bool>> _checkForUpdatesViaApi() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await _dio.get<Map<String, dynamic>>(
        '$_updateUrl/check',
        queryParameters: {'currentVersion': currentVersion},
      );

      if (response.statusCode != 200) {
        return Failure(
          domain.ServerFailure.withContext(
            message: 'Unable to verify updates right now',
            context: {
              'operation': 'checkForUpdates',
              'statusCode': response.statusCode,
            },
          ),
        );
      }

      final data = response.data;
      if (data == null) {
        return Failure(
          domain.ServerFailure.withContext(
            message: 'Update server returned an empty response',
            context: {'operation': 'checkForUpdates'},
          ),
        );
      }
      final isUpdateAvailable = data['updateAvailable'] as bool? ?? false;

      return Success(isUpdateAvailable);
    } on DioException catch (error) {
      return Failure(
        domain.NetworkFailure.withContext(
          message:
              'Unable to check for updates. Check your connection and try again.',
          cause: error,
          context: {'operation': 'checkForUpdates'},
        ),
      );
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Failed to check for updates',
          cause: error,
          context: {'operation': 'checkForUpdates'},
        ),
      );
    }
  }
}
