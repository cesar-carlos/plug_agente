import 'package:auto_updater/auto_updater.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class UpdateService {
  UpdateService(this._updateUrl);
  final String _updateUrl;
  static const int _minimumScheduledCheckIntervalSeconds = 3600;

  Future<Result<bool>> checkForUpdates() async {
    if (isSparkleFeedUrl(_updateUrl)) {
      return _checkForUpdatesViaSparkle();
    }
    return Failure(
      domain.ConfigurationFailure.withContext(
        message:
            'Auto-update is not configured. Set AUTO_UPDATE_FEED_URL with a Sparkle feed (.xml).',
        context: {'operation': 'checkForUpdates'},
      ),
    );
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
}
