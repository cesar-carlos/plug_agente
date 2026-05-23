// ignore_for_file: avoid_print

/// Obtains E2E_HUB_TOKEN from local config, Hub login, or `.env` credentials.
///
/// Never prints the token.
///
/// Usage:
///   `dart run tool/fetch_e2e_hub_token_from_local_config.dart`
///   `dart run tool/fetch_e2e_hub_token_from_local_config.dart --apply-token`
///   `dart run tool/fetch_e2e_hub_token_from_local_config.dart --apply-token --force`
library;

import 'dart:io';

import 'src/dot_env_patch.dart';
import 'src/e2e_hub_login_from_env.dart';
import 'src/hub_auth_login.dart';
import 'src/live_hub_agent_action_env_check.dart';
import 'src/local_agent_config_reader.dart';

Future<({String token, String source})?> _resolveFromLocalConfig(
  LocalAgentHubConfig config, {
  String? loginServerUrl,
  String? agentId,
  bool preferLoginOverCachedToken = false,
}) async {
  final effectiveServerUrl = loginServerUrl ?? hubHttpLoginServerUrl(config.serverUrl);
  final effectiveAgentId = (agentId ?? config.agentId).trim();
  final localToken = config.authToken?.trim();
  final refreshToken = config.refreshToken?.trim();
  final tokenWarnings = liveHubTokenWarnings(localToken);
  final tokenExpired = tokenWarnings.any((warning) => warning.contains('JWT is expired'));

  if (!preferLoginOverCachedToken && localToken != null && localToken.isNotEmpty && !tokenExpired) {
    return (token: localToken, source: 'local config / secure storage auth token');
  }
  if (refreshToken != null && refreshToken.isNotEmpty) {
    try {
      final result = await refreshHubAgentSession(
        serverUrl: effectiveServerUrl,
        refreshToken: refreshToken,
      );
      return (
        token: result.accessToken,
        source: 'Hub refresh (saved refresh token in local config / secure storage)',
      );
    } on HubLoginException {
      // Fall through to username/password login when refresh is stale.
    }
  }
  if (!config.hasStoredCredentials) {
    if (!preferLoginOverCachedToken && localToken != null && localToken.isNotEmpty) {
      return (token: localToken, source: 'local config / secure storage auth token');
    }
    return null;
  }
  final result = await loginHubAgent(
    serverUrl: effectiveServerUrl,
    agentId: effectiveAgentId,
    username: config.authUsername!.trim(),
    password: config.authPassword!.trim(),
  );
  final loginTarget = loginServerUrl == null ? 'saved credentials in local config / secure storage' : 'saved credentials against E2E_HUB_URL';
  return (token: result.accessToken, source: 'Hub login ($loginTarget)');
}

bool _envHubLoginDiffersFromConfig({
  required String? envHubUrl,
  required String configServerUrl,
}) {
  if (envHubUrl == null || isPlaceholderServerUrl(envHubUrl)) {
    return false;
  }
  return hubHttpLoginServerUrl(envHubUrl) != hubHttpLoginServerUrl(configServerUrl);
}

Future<({String token, String source})?> _resolveFromEnvCredentials(String projectRoot) async {
  final envLogin = readE2eHubLoginFromRepoEnv(projectRoot);
  if (envLogin == null) {
    return null;
  }
  final result = await loginHubAgent(
    serverUrl: envLogin.serverUrl,
    agentId: envLogin.agentId,
    username: envLogin.username,
    password: envLogin.password,
  );
  return (token: result.accessToken, source: 'Hub login (E2E_HUB_USERNAME in .env)');
}

void main(List<String> args) async {
  final applyToken = args.contains('--apply-token');
  final forceToken = args.contains('--force');
  final projectRoot = Directory.current.path;

  try {
    ({String token, String source})? resolved;

    final fileEnv = loadRepoEnvFile(projectRoot);
    final envHubUrl = envValue(fileEnv, 'E2E_HUB_URL');
    final envAgentId = envValue(fileEnv, 'E2E_HUB_AGENT_ID');
    final loginServerUrl =
        envHubUrl != null && !isPlaceholderServerUrl(envHubUrl) ? hubHttpLoginServerUrl(envHubUrl) : null;

    final config = readLatestResolvedLocalAgentHubConfig();
    if (config != null && !isPlaceholderServerUrl(config.serverUrl)) {
      final preferLoginOverCachedToken =
          forceToken ||
          _envHubLoginDiffersFromConfig(envHubUrl: envHubUrl, configServerUrl: config.serverUrl);
      resolved = await _resolveFromLocalConfig(
        config,
        loginServerUrl: loginServerUrl,
        agentId: envAgentId,
        preferLoginOverCachedToken: preferLoginOverCachedToken,
      );
    }

    resolved ??= await _resolveFromEnvCredentials(projectRoot);

    if (resolved == null) {
      if (config == null) {
        print('[info] No agent_config.db and no E2E_HUB_USERNAME/E2E_HUB_PASSWORD in .env.');
      } else if (isPlaceholderServerUrl(config.serverUrl)) {
        print('[warn] server_url is still the placeholder — configure Hub URL in the app first.');
      } else {
        print('[info] No auth_token in config_table and no saved username/password.');
      }
      print('  Options:');
      print('    - Sign in via Config in the app, then re-run this tool');
      print('    - Set E2E_HUB_USERNAME, E2E_HUB_PASSWORD, E2E_HUB_URL, E2E_HUB_AGENT_ID in .env');
      print('    - Set E2E_HUB_TOKEN manually in .env');
      exit(1);
    }

    final (:token, :source) = resolved;
    if (token.isEmpty) {
      print('[fail] Could not resolve access token.');
      exit(1);
    }

    print('[ok] Access token resolved from $source (value not shown).');

    if (applyToken) {
      final patched = patchDotEnvKey(
        projectRoot: projectRoot,
        key: 'E2E_HUB_TOKEN',
        value: token,
        onlyIfEmpty: !forceToken,
      );
      if (patched) {
        print('[ok] Wrote E2E_HUB_TOKEN to .env.');
      } else if (!forceToken && !dotEnvKeyIsEmpty(projectRoot, 'E2E_HUB_TOKEN')) {
        print('[skip] E2E_HUB_TOKEN already set — not overwritten (use --force to replace).');
      } else {
        print('[skip] E2E_HUB_TOKEN unchanged in .env.');
      }
    } else {
      print('Run with --apply-token to write E2E_HUB_TOKEN when the line is empty.');
      print('      Add --force to replace an existing (e.g. expired) token.');
    }

    print('Next: dart run tool/validate_live_hub_agent_actions_env.dart');
  } on HubLoginException catch (error) {
    print('[fail] Hub login failed: ${error.message}');
    exit(1);
  }
}
