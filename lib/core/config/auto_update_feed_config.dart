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
