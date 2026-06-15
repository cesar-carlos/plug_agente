// ignore_for_file: avoid_print

/// Suggests E2E Hub variables from local Plug Agente storage (no secrets printed).
///
/// Usage:
///   `dart run tool/e2e/suggest_e2e_hub_from_local_config.dart`
///   `dart run tool/e2e/suggest_e2e_hub_from_local_config.dart --apply-url`
///   `dart run tool/e2e/suggest_e2e_hub_from_local_config.dart --apply-agent-id`
library;

import 'dart:io';

import '../src/dot_env_patch.dart';
import '../src/live_hub_agent_action_env_check.dart';
import '../src/local_agent_config_reader.dart';

void _attachSigningHintsFromRepoEnv(String projectRoot) {
  final fileEnv = loadRepoEnvFile(projectRoot);
  final keyId = envValue(fileEnv, 'PAYLOAD_SIGNING_KEY_ID') ?? envValue(fileEnv, 'PAYLOAD_SIGNING_ACTIVE_KEY_ID');
  final key = envValue(fileEnv, 'PAYLOAD_SIGNING_KEY');
  print(
    '  PAYLOAD_SIGNING in .env (hub block): '
    'key_id=${keyId != null && keyId.isNotEmpty ? "set" : "empty"}, '
    'key=${key != null && key.isNotEmpty ? "set" : "empty"}',
  );
  if (envValue(fileEnv, 'PAYLOAD_SIGNING_KEYS_JSON') != null || envValue(fileEnv, 'PAYLOAD_SIGNING_KEYS') != null) {
    print('  Note: PAYLOAD_SIGNING_KEYS_JSON/KEYS found elsewhere in .env (E2E still needs KEY_ID + KEY).');
  }
}

void main(List<String> args) {
  final applyUrl = args.contains('--apply-url');
  final applyAgentId = args.contains('--apply-agent-id');
  if (!Platform.isWindows) {
    print('[warn] This helper targets Windows PlugAgente storage paths.');
  }

  final projectRoot = Directory.current.path;
  final config = readLatestLocalAgentHubConfig();
  if (config == null) {
    print('[info] No agent_config.db found under PlugAgente storage candidates.');
    print('  Configure E2E_HUB_URL manually (see docs/testing/e2e_setup.md).');
    exit(1);
  }

  final dbPath = findAgentConfigDatabasePath();
  print('[ok] Found database: $dbPath');
  print('  config_id: ${config.configId.isEmpty ? "(empty)" : config.configId}');
  print('  agent_id: ${config.agentId.isEmpty ? "(empty)" : config.agentId}');
  print('  auth_token in config_table: ${config.hasAuthTokenInDb ? "present (not shown)" : "missing"}');
  if (config.hasStoredCredentials) {
    print('  saved credentials: present (use fetch_e2e_hub_token_from_local_config.dart --apply-token)');
  }

  if (isPlaceholderServerUrl(config.serverUrl)) {
    print('[warn] server_url is still the placeholder — set Server URL in Config and save.');
    exit(1);
  }

  final suggestedHubUrl = config.hubAgentsUrl;
  if (applyAgentId && config.agentId.isNotEmpty) {
    final patched = patchDotEnvKey(
      projectRoot: projectRoot,
      key: 'E2E_HUB_AGENT_ID',
      value: config.agentId,
      onlyIfEmpty: false,
    );
    if (patched) {
      print('[ok] Wrote E2E_HUB_AGENT_ID to .env (matches local agent_config.db).');
    } else {
      print('[skip] E2E_HUB_AGENT_ID unchanged in .env.');
    }
  }

  if (applyUrl) {
    final patched = patchDotEnvKey(
      projectRoot: projectRoot,
      key: 'E2E_HUB_URL',
      value: suggestedHubUrl,
    );
    if (patched) {
      print('[ok] Wrote E2E_HUB_URL to .env (non-secret).');
    } else if (!dotEnvKeyIsEmpty(projectRoot, 'E2E_HUB_URL')) {
      print('[skip] E2E_HUB_URL already set in .env - not overwritten.');
    } else {
      print('[warn] Could not patch .env — copy E2E_HUB_URL manually.');
    }
  }

  print('');
  print('Suggested .env lines (copy secrets yourself; never printed here):');
  print('  E2E_HUB_URL=$suggestedHubUrl');
  if (config.agentId.isNotEmpty) {
    print('  E2E_HUB_AGENT_ID=${config.agentId}');
  }
  if (config.hasAuthTokenInDb || config.hasStoredCredentials) {
    print('  E2E_HUB_TOKEN=<dart run tool/e2e/fetch_e2e_hub_token_from_local_config.dart --apply-token>');
  } else {
    print('  E2E_HUB_TOKEN=<login in app (Config) or set token from Hub admin>');
  }
  print('  PAYLOAD_SIGNING_KEY_ID=<from Hub server or app signing config>');
  print('  PAYLOAD_SIGNING_KEY=<same secret as Hub>');
  _attachSigningHintsFromRepoEnv(projectRoot);
  print('');
  print('Then: dart run tool/e2e/validate_live_hub_agent_actions_env.dart');
  if (!applyUrl || !applyAgentId) {
    print(
      'Tip:   dart run tool/e2e/suggest_e2e_hub_from_local_config.dart --apply-url --apply-agent-id',
    );
  }
}
