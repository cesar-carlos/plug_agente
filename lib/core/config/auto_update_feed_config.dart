String resolveAutoUpdateFeedUrl({
  required Map<String, String> environment,
  String? fromDefine,
}) {
  final normalizedFromDefine =
      (fromDefine ?? const String.fromEnvironment('AUTO_UPDATE_FEED_URL'))
          .trim();
  if (normalizedFromDefine.isNotEmpty) {
    return normalizedFromDefine;
  }
  return environment['AUTO_UPDATE_FEED_URL']?.trim() ?? '';
}

bool isSparkleFeedUrl(String url) {
  final normalized = url.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  final withoutQuery = normalized.split('?').first;
  return withoutQuery.endsWith('.xml');
}

const int _defaultCheckIntervalSeconds = 3600;
const int _minimumCheckIntervalSeconds = 300;

int resolveAutoUpdateCheckIntervalSeconds({
  required Map<String, String> environment,
}) {
  final raw =
      environment['AUTO_UPDATE_CHECK_INTERVAL_SECONDS']?.trim() ?? '';
  if (raw.isEmpty) return _defaultCheckIntervalSeconds;
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < _minimumCheckIntervalSeconds) {
    return _defaultCheckIntervalSeconds;
  }
  return parsed;
}
