const String officialAutoUpdateFeedUrl = 'https://cesar-carlos.github.io/plug_agente/appcast.xml';

String? resolveAutoUpdateFeedOverride({
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
  return null;
}

String resolveAutoUpdateFeedUrl({
  required Map<String, String> environment,
  String? fromDefine,
}) {
  final override = resolveAutoUpdateFeedOverride(
    environment: environment,
    fromDefine: fromDefine,
  );
  if (override != null) {
    return override;
  }
  return officialAutoUpdateFeedUrl;
}

bool isSparkleFeedUrl(String url) {
  return _isAllowedAutoUpdateUrl(
    url,
    requiredExtension: '.xml',
  );
}

bool isAutoUpdateInstallerUrl(String url) {
  return _isAllowedAutoUpdateUrl(
    url,
    requiredExtension: '.exe',
  );
}

bool _isAllowedAutoUpdateUrl(
  String url, {
  required String requiredExtension,
}) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || !uri.hasAuthority || uri.host.isEmpty) {
    return false;
  }

  if (!uri.path.toLowerCase().endsWith(requiredExtension)) {
    return false;
  }

  return _usesAllowedAutoUpdateTransport(uri);
}

bool _usesAllowedAutoUpdateTransport(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https') {
    return true;
  }

  return scheme == 'http' && _isLoopbackHost(uri.host);
}

bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' || normalized == '127.0.0.1' || normalized == '::1';
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

bool hasInvalidAutoUpdateFeedOverride({
  required Map<String, String> environment,
  String? fromDefine,
}) {
  final override = resolveAutoUpdateFeedOverride(
    environment: environment,
    fromDefine: fromDefine,
  );
  if (override == null) {
    return false;
  }
  return !isSparkleFeedUrl(override);
}

const int _defaultCheckIntervalSeconds = 3600;
const int _minimumCheckIntervalSeconds = 3600;
const String defaultAutoUpdateChannel = 'stable';

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

String resolveAutoUpdateChannel({
  required Map<String, String> environment,
  String? fromDefine,
}) {
  final raw = (fromDefine ?? const String.fromEnvironment('AUTO_UPDATE_CHANNEL')).trim();
  final environmentValue = raw.isNotEmpty ? raw : environment['AUTO_UPDATE_CHANNEL']?.trim() ?? '';
  if (environmentValue.isEmpty) {
    return defaultAutoUpdateChannel;
  }
  return environmentValue.toLowerCase();
}

bool resolveAutoUpdateRequireValidSignature({
  required Map<String, String> environment,
  String? fromDefine,
}) {
  final raw = (fromDefine ?? const String.fromEnvironment('AUTO_UPDATE_REQUIRE_VALID_SIGNATURE')).trim();
  final value = raw.isNotEmpty ? raw : environment['AUTO_UPDATE_REQUIRE_VALID_SIGNATURE']?.trim() ?? '';
  return switch (value.toLowerCase()) {
    '1' || 'true' || 'yes' || 'sim' => true,
    _ => false,
  };
}
