/// Pure-Dart live Hub `agent.action.*` environment checks (no Flutter).
///
/// Used by `validate_live_hub_agent_actions_env.dart` and mirrored in
/// `test/helpers/e2e_env.dart` for integration tests.
library;

import 'dart:convert';
import 'dart:io';

List<String> missingLiveHubAgentActionVariables({
  required bool runLiveHubTests,
  required bool runLiveHubSigningTests,
  required bool runLiveHubAgentActionRpcTests,
  required String? hubUrl,
  required String? hubToken,
  required String? payloadSigningKeyId,
  required String? payloadSigningKey,
}) {
  final missing = <String>[];
  if (!runLiveHubTests) {
    missing.add('RUN_LIVE_HUB_TESTS');
  }
  if (!runLiveHubAgentActionRpcTests) {
    missing.add('RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS');
  }
  if (!runLiveHubSigningTests) {
    missing.add('RUN_LIVE_HUB_SIGNING_TESTS');
  }
  if (hubUrl == null || hubUrl.trim().isEmpty) {
    missing.add('E2E_HUB_URL');
  }
  if (hubToken == null || hubToken.trim().isEmpty) {
    missing.add('E2E_HUB_TOKEN');
  }
  if (payloadSigningKeyId == null || payloadSigningKeyId.trim().isEmpty) {
    missing.add('PAYLOAD_SIGNING_KEY_ID or PAYLOAD_SIGNING_ACTIVE_KEY_ID');
  }
  if (payloadSigningKey == null || payloadSigningKey.trim().isEmpty) {
    missing.add('PAYLOAD_SIGNING_KEY');
  }
  return missing;
}

Map<String, String> loadRepoEnvFile(String projectRoot) {
  final result = <String, String>{};
  final file = File('$projectRoot${Platform.pathSeparator}.env');
  if (!file.existsSync()) {
    return result;
  }
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final idx = trimmed.indexOf('=');
    if (idx <= 0) {
      continue;
    }
    final key = trimmed.substring(0, idx).trim();
    var value = trimmed.substring(idx + 1).trim();
    if (value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    } else if (value.startsWith("'") && value.endsWith("'")) {
      value = value.substring(1, value.length - 1);
    }
    result[key] = value;
  }
  return result;
}

String? envValue(Map<String, String> fileEnv, String key) {
  final fromProcess = Platform.environment[key]?.trim();
  if (fromProcess != null && fromProcess.isNotEmpty) {
    return fromProcess;
  }
  final fromFile = fileEnv[key]?.trim();
  if (fromFile != null && fromFile.isNotEmpty) {
    return fromFile;
  }
  return null;
}

bool envFlag(Map<String, String> fileEnv, String key) => envValue(fileEnv, key) == 'true';

/// Whether a boolean env var is explicitly set to `false` (vs absent).
bool envFlagExplicitlyFalse(Map<String, String> fileEnv, String key) =>
    envValue(fileEnv, key)?.toLowerCase() == 'false';

List<String> commentedHubKeysInDotEnv(String projectRoot) {
  final file = File('$projectRoot${Platform.pathSeparator}.env');
  if (!file.existsSync()) {
    return const <String>[];
  }
  final keys = <String>[];
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('#')) {
      continue;
    }
    final body = trimmed.substring(1).trim();
    final idx = body.indexOf('=');
    if (idx <= 0) {
      continue;
    }
    final key = body.substring(0, idx).trim();
    if (_hubLiveKeys.contains(key)) {
      keys.add(key);
    }
  }
  return keys;
}

const Set<String> _hubLiveKeys = <String>{
  'RUN_LIVE_HUB_TESTS',
  'RUN_LIVE_HUB_SIGNING_TESTS',
  'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS',
  'E2E_HUB_URL',
  'E2E_HUB_TOKEN',
  'PAYLOAD_SIGNING_KEY_ID',
  'PAYLOAD_SIGNING_ACTIVE_KEY_ID',
  'PAYLOAD_SIGNING_KEY',
};

List<String> missingFromRepoEnv(Map<String, String> fileEnv) {
  return missingLiveHubAgentActionVariables(
    runLiveHubTests: envFlag(fileEnv, 'RUN_LIVE_HUB_TESTS'),
    runLiveHubSigningTests: envFlag(fileEnv, 'RUN_LIVE_HUB_SIGNING_TESTS'),
    runLiveHubAgentActionRpcTests: envFlag(fileEnv, 'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS'),
    hubUrl: envValue(fileEnv, 'E2E_HUB_URL'),
    hubToken: envValue(fileEnv, 'E2E_HUB_TOKEN'),
    payloadSigningKeyId:
        envValue(fileEnv, 'PAYLOAD_SIGNING_KEY_ID') ?? envValue(fileEnv, 'PAYLOAD_SIGNING_ACTIVE_KEY_ID'),
    payloadSigningKey: envValue(fileEnv, 'PAYLOAD_SIGNING_KEY'),
  );
}

String projectRootFromScript() {
  final scriptPath = Platform.script.toFilePath();
  final toolDir = File(scriptPath).parent;
  return toolDir.parent.path;
}

/// JWT `exp` claim in seconds since epoch, or null when not decodable.
int? jwtExpiryEpochSeconds(String? token) {
  final trimmed = token?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final parts = trimmed.split('.');
  if (parts.length < 2) {
    return null;
  }
  try {
    var payloadSegment = parts[1];
    final padding = (4 - payloadSegment.length % 4) % 4;
    if (padding > 0) {
      payloadSegment = '$payloadSegment${'=' * padding}';
    }
    final decoded = utf8.decode(base64Url.decode(payloadSegment));
    final Object? parsed = jsonDecode(decoded);
    if (parsed is! Map<String, Object?>) {
      return null;
    }
    final exp = parsed['exp'];
    if (exp is int) {
      return exp;
    }
    if (exp is num) {
      return exp.toInt();
    }
    return null;
  } on Object {
    return null;
  }
}

/// Non-fatal hints for the `E2E_HUB_TOKEN` env var before opening Socket.IO.
List<String> liveHubTokenWarnings(String? hubToken) {
  final exp = jwtExpiryEpochSeconds(hubToken);
  if (exp == null) {
    return const <String>[];
  }
  final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  if (exp <= nowSeconds) {
    const expiredMessage =
        'E2E_HUB_TOKEN JWT is expired — Hub connect will fail with jwt expired. '
        'Refresh: dart run tool/fetch_e2e_hub_token_from_local_config.dart '
        '--apply-token --force';
    return <String>[expiredMessage];
  }
  const soonThresholdSeconds = 3600;
  if (exp - nowSeconds <= soonThresholdSeconds) {
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    final soonMessage =
        'E2E_HUB_TOKEN JWT expires soon (at ${expiresAt.toIso8601String()}). '
        'Consider refreshing before a long live run.';
    return <String>[soonMessage];
  }
  return const <String>[];
}

List<String> liveHubTokenBlockingFailures(String? hubToken) {
  final exp = jwtExpiryEpochSeconds(hubToken);
  if (exp == null) {
    return const <String>[];
  }
  final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  if (exp > nowSeconds) {
    return const <String>[];
  }
  const expiredMessage =
      'E2E_HUB_TOKEN JWT is expired - Hub connect will fail with jwt expired. '
      'Refresh: dart run tool/fetch_e2e_hub_token_from_local_config.dart '
      '--apply-token --force';
  return const <String>[expiredMessage];
}

/// Non-fatal hints when `.env` is syntactically complete but likely wrong for a remote Hub.
List<String> liveHubEnvWarnings({
  required String? hubUrl,
  required String? payloadSigningKeyId,
  String? hubToken,
}) {
  final warnings = <String>[];
  final url = hubUrl?.trim().toLowerCase() ?? '';
  final keyId = payloadSigningKeyId?.trim().toLowerCase() ?? '';
  final isLocalHub = url.contains('localhost') || url.contains('127.0.0.1') || url.contains('0.0.0.0');
  if (keyId == 'e2e-dev' && url.isNotEmpty && !isLocalHub) {
    warnings.add(
      'PAYLOAD_SIGNING_KEY_ID is e2e-dev while E2E_HUB_URL targets a remote hub — '
      'agent:capabilities will time out unless the server uses the same dev HMAC pair.',
    );
  }
  warnings.addAll(liveHubTokenWarnings(hubToken));
  return warnings;
}

/// Blocking preflight failures before opening a live Hub Socket.IO connection.
///
/// Missing variables are intentionally left to the test-level skip logic. This
/// function flags values that are present but known to produce an avoidable
/// connect/register failure.
List<String> blockingLiveHubEnvFailures({
  required bool runLiveHubTests,
  required String? hubUrl,
  required String? hubToken,
  String? payloadSigningKeyId,
}) {
  if (!runLiveHubTests) {
    return const <String>[];
  }
  if (hubUrl == null || hubUrl.trim().isEmpty || hubToken == null || hubToken.trim().isEmpty) {
    return const <String>[];
  }
  final failures = <String>[];
  final url = hubUrl.trim().toLowerCase();
  final keyId = payloadSigningKeyId?.trim().toLowerCase() ?? '';
  final isLocalHub = url.contains('localhost') || url.contains('127.0.0.1') || url.contains('0.0.0.0');
  if (keyId == 'e2e-dev' && url.isNotEmpty && !isLocalHub) {
    failures.add(
      'PAYLOAD_SIGNING_KEY_ID is e2e-dev while E2E_HUB_URL targets a remote hub - '
      'copy PAYLOAD_SIGNING_* from the deployed Hub environment before running signed live tests.',
    );
  }
  failures.addAll(liveHubTokenBlockingFailures(hubToken));
  return failures;
}
