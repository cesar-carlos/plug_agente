/// Optional Hub agent login credentials from `.env` (E2E only, values never logged).
library;

import 'hub_url_for_e2e.dart';
import 'live_hub_agent_action_env_check.dart';

/// Credentials for `loginHubAgent` when set in `.env` / process environment.
class E2eHubLoginFromEnv {
  const E2eHubLoginFromEnv({
    required this.serverUrl,
    required this.agentId,
    required this.username,
    required this.password,
  });

  final String serverUrl;
  final String agentId;
  final String username;
  final String password;
}

/// Base Hub URL for HTTP login (strips `/agents` when [hubUrl] is the Socket namespace).
String hubHttpLoginServerUrl(String hubUrl) {
  final normalized = normalizeServerUrl(hubUrl);
  if (normalized.isEmpty) {
    return normalized;
  }
  final parsedUri = Uri.tryParse(normalized);
  if (parsedUri != null && parsedUri.hasScheme) {
    final segments = parsedUri.pathSegments.where((String s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty && segments.last.toLowerCase() == 'agents') {
      segments.removeLast();
      return parsedUri.replace(pathSegments: segments).toString();
    }
    return normalized;
  }
  final lower = normalized.toLowerCase();
  const suffix = '/agents';
  if (lower.endsWith(suffix)) {
    return normalized.substring(0, normalized.length - suffix.length);
  }
  return normalized;
}

/// Reads `E2E_HUB_USERNAME`, `E2E_HUB_PASSWORD`, `E2E_HUB_URL`, `E2E_HUB_AGENT_ID`.
E2eHubLoginFromEnv? readE2eHubLoginFromRepoEnv(String projectRoot) {
  final fileEnv = loadRepoEnvFile(projectRoot);
  return readE2eHubLoginFromEnvMap(fileEnv);
}

E2eHubLoginFromEnv? readE2eHubLoginFromEnvMap(Map<String, String> fileEnv) {
  final username = envValue(fileEnv, 'E2E_HUB_USERNAME');
  final password = envValue(fileEnv, 'E2E_HUB_PASSWORD');
  final hubUrl = envValue(fileEnv, 'E2E_HUB_URL');
  final agentId = envValue(fileEnv, 'E2E_HUB_AGENT_ID');
  if (username == null || password == null || hubUrl == null || agentId == null || isPlaceholderServerUrl(hubUrl)) {
    return null;
  }
  return E2eHubLoginFromEnv(
    serverUrl: hubHttpLoginServerUrl(hubUrl),
    agentId: agentId,
    username: username,
    password: password,
  );
}
