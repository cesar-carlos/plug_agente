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

const int _defaultDownloadTimeoutSeconds = 300;
const int _minimumDownloadTimeoutSeconds = 60;

int resolveAutoUpdateDownloadTimeoutSeconds({
  required Map<String, String> environment,
}) {
  final raw = environment['AUTO_UPDATE_DOWNLOAD_TIMEOUT_SECONDS']?.trim() ?? '';
  if (raw.isEmpty) return _defaultDownloadTimeoutSeconds;
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < _minimumDownloadTimeoutSeconds) {
    return _defaultDownloadTimeoutSeconds;
  }
  return parsed;
}

const int _defaultHelperWaitMinutes = 30;
const int _minimumHelperWaitMinutes = 5;
const int _maximumHelperWaitMinutes = 120;

int resolveAutoUpdateHelperWaitMinutes({
  required Map<String, String> environment,
}) {
  final raw = environment['AUTO_UPDATE_HELPER_WAIT_MINUTES']?.trim() ?? '';
  if (raw.isEmpty) return _defaultHelperWaitMinutes;
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < _minimumHelperWaitMinutes || parsed > _maximumHelperWaitMinutes) {
    return _defaultHelperWaitMinutes;
  }
  return parsed;
}

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
    '0' || 'false' || 'no' || 'nao' => false,
    _ => true,
  };
}

/// Base64-encoded Ed25519 public key used to verify the optional
/// `plug:edSignature` attribute on the appcast feed. Returns `null` when the
/// operator has not configured a key (typical for builds where feed signing
/// is not yet rolled out).
///
/// Resolution order: `--dart-define=AUTO_UPDATE_FEED_PUBLIC_KEY=...` first,
/// then `.env`, then `null` (no verification).
String? resolveAutoUpdateFeedPublicKey({
  required Map<String, String> environment,
  String? fromDefine,
}) {
  final raw = (fromDefine ?? const String.fromEnvironment('AUTO_UPDATE_FEED_PUBLIC_KEY')).trim();
  if (raw.isNotEmpty) return raw;
  final fromEnv = environment['AUTO_UPDATE_FEED_PUBLIC_KEY']?.trim() ?? '';
  return fromEnv.isEmpty ? null : fromEnv;
}

/// When `true`, the silent update flow rejects appcast items whose
/// Ed25519 signature does not verify against
/// [resolveAutoUpdateFeedPublicKey]. Defaults to `false` so existing
/// (unsigned) releases continue to work until the signing pipeline is
/// rolled out end-to-end.
///
/// Setting this to `true` without configuring
/// [resolveAutoUpdateFeedPublicKey] will block every silent check
/// (`publicKeyUnavailable`); operators must ship both env vars together.
bool resolveAutoUpdateRequireFeedSignature({
  required Map<String, String> environment,
  String? fromDefine,
}) {
  final raw = (fromDefine ?? const String.fromEnvironment('AUTO_UPDATE_REQUIRE_FEED_SIGNATURE')).trim();
  final value = raw.isNotEmpty ? raw : environment['AUTO_UPDATE_REQUIRE_FEED_SIGNATURE']?.trim() ?? '';
  return switch (value.toLowerCase()) {
    '1' || 'true' || 'yes' || 'sim' => true,
    _ => false,
  };
}

const int _defaultPreCloseDelaySeconds = 30;
const int _maxPreCloseDelaySeconds = 120;

/// Delay (in seconds) between the moment the silent flow decides to close
/// the app and the actual close. Used to display a "app fechando para
/// instalar atualizacao" notice. Default 30s, capped between 0 and 120.
int resolveAutoUpdatePreCloseDelaySeconds({
  required Map<String, String> environment,
}) {
  final raw = environment['AUTO_UPDATE_PRE_CLOSE_DELAY_SECONDS']?.trim() ?? '';
  if (raw.isEmpty) return _defaultPreCloseDelaySeconds;
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < 0 || parsed > _maxPreCloseDelaySeconds) {
    return _defaultPreCloseDelaySeconds;
  }
  return parsed;
}

/// Parses an `HH:MM` string into minutes since midnight (`0..1439`).
/// Returns `null` when [raw] is null/blank/malformed. Tolerates surrounding
/// whitespace and single-digit hours/minutes.
int? parseQuietHourMinute(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

/// Start of the quiet-hours window in minutes since midnight, or `null` when
/// not configured. Together with [resolveAutoUpdateQuietHoursEndMinute],
/// the silent flow returns `skippedByQuietHours` instead of probing when
/// the current local time falls inside `[start, end)`. Wrap-around (start
/// > end) is supported, e.g., `start=22:00`, `end=06:00`.
int? resolveAutoUpdateQuietHoursStartMinute({
  required Map<String, String> environment,
}) {
  return parseQuietHourMinute(environment['AUTO_UPDATE_QUIET_HOURS_START']);
}

/// End of the quiet-hours window in minutes since midnight, or `null`.
int? resolveAutoUpdateQuietHoursEndMinute({
  required Map<String, String> environment,
}) {
  return parseQuietHourMinute(environment['AUTO_UPDATE_QUIET_HOURS_END']);
}

/// True when [nowMinutes] (minutes since local midnight) falls inside the
/// window `[startMinute, endMinute)`. Supports overnight windows where
/// `start > end`. Returns `false` when either bound is null.
bool isWithinQuietHoursWindow({
  required int nowMinutes,
  required int? startMinute,
  required int? endMinute,
}) {
  if (startMinute == null || endMinute == null) return false;
  if (startMinute == endMinute) return false;
  if (startMinute < endMinute) {
    return nowMinutes >= startMinute && nowMinutes < endMinute;
  }
  // Overnight window: e.g., 22:00..06:00.
  return nowMinutes >= startMinute || nowMinutes < endMinute;
}

/// Whether the silent updater is allowed to resume a partial download by
/// issuing an HTTP `Range` request when a `.part` file from a previous
/// attempt is still on disk. Defaults to `true` because it strictly improves
/// reliability on flaky links; set to `false` to opt out (e.g., for hubs that
/// proxy the asset and do not honor `Range`).
bool resolveAutoUpdateDownloadResume({
  required Map<String, String> environment,
  String? fromDefine,
}) {
  final raw = (fromDefine ?? const String.fromEnvironment('AUTO_UPDATE_DOWNLOAD_RESUME')).trim();
  final value = raw.isNotEmpty ? raw : environment['AUTO_UPDATE_DOWNLOAD_RESUME']?.trim() ?? '';
  return switch (value.toLowerCase()) {
    '0' || 'false' || 'no' || 'nao' => false,
    _ => true,
  };
}
