const String officialAutoUpdateFeedUrl = 'https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml';

String resolveAutoUpdateFeedUrl({
  required Map<String, String> environment,
  String? fromDefine,
}) {
  final normalizedFromDefine = (fromDefine ?? const String.fromEnvironment('AUTO_UPDATE_FEED_URL')).trim();
  if (normalizedFromDefine.isNotEmpty) {
    return normalizedFromDefine;
  }
  final normalizedFromEnvironment = environment['AUTO_UPDATE_FEED_URL']?.trim() ?? '';
  if (normalizedFromEnvironment.isNotEmpty) {
    return normalizedFromEnvironment;
  }
  return officialAutoUpdateFeedUrl;
}

bool isSparkleFeedUrl(String url) {
  final normalized = url.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  final withoutQuery = normalized.split('?').first;
  return withoutQuery.endsWith('.xml');
}

bool isOfficialAutoUpdateFeedUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  final officialUri = Uri.parse(officialAutoUpdateFeedUrl);
  if (uri == null) return false;

  return uri.scheme.toLowerCase() == officialUri.scheme.toLowerCase() &&
      uri.host.toLowerCase() == officialUri.host.toLowerCase() &&
      uri.port == officialUri.port &&
      uri.path == officialUri.path;
}

const int _defaultCheckIntervalSeconds = 3600;
const int _minimumCheckIntervalSeconds = 3600;

int resolveAutoUpdateCheckIntervalSeconds({
  required Map<String, String> environment,
}) {
  final raw = environment['AUTO_UPDATE_CHECK_INTERVAL_SECONDS']?.trim() ?? '';
  if (raw.isEmpty) return _defaultCheckIntervalSeconds;
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < _minimumCheckIntervalSeconds) {
    return _defaultCheckIntervalSeconds;
  }
  return parsed;
}
