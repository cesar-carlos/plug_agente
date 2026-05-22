// ignore_for_file: avoid_print

/// Copies non-empty PAYLOAD_SIGNING_* from sibling repo `.env` files into plug_agente.
///
/// Usage:
///   `dart run tool/promote_e2e_signing_from_monorepo_env.dart`
///   `dart run tool/promote_e2e_signing_from_monorepo_env.dart --force`
library;

import 'dart:io';

import 'src/dot_env_patch.dart';
import 'src/e2e_monorepo_env_paths.dart';
import 'src/live_hub_agent_action_env_check.dart';

void main(List<String> args) {
  final force = args.contains('--force');
  final projectRoot = Directory.current.path;
  var foundSource = false;
  var patched = false;
  String? sourceEnvPath;
  String? sourceKeyId;
  String? sourceKey;

  for (final envPath in siblingHubEnvFileCandidates(projectRoot)) {
    final file = File(envPath);
    if (!file.existsSync()) {
      continue;
    }
    final fileEnv = _loadEnvFile(envPath);
    final keyId = _nonEmpty(fileEnv, 'PAYLOAD_SIGNING_KEY_ID') ?? _nonEmpty(fileEnv, 'PAYLOAD_SIGNING_ACTIVE_KEY_ID');
    final key = _nonEmpty(fileEnv, 'PAYLOAD_SIGNING_KEY');
    if (keyId == null || key == null) {
      print('[ ] $envPath — PAYLOAD_SIGNING_* empty or missing');
      continue;
    }
    foundSource = true;
    sourceEnvPath = envPath;
    sourceKeyId = keyId;
    sourceKey = key;
    print('[ok] Source: $envPath (values not shown)');
    patched =
        patchDotEnvKey(
          projectRoot: projectRoot,
          key: 'PAYLOAD_SIGNING_KEY_ID',
          value: keyId,
          onlyIfEmpty: !force,
        ) ||
        patched;
    patched =
        patchDotEnvKey(
          projectRoot: projectRoot,
          key: 'PAYLOAD_SIGNING_KEY',
          value: key,
          onlyIfEmpty: !force,
        ) ||
        patched;
    break;
  }

  if (!foundSource) {
    print('[info] No sibling .env with non-empty PAYLOAD_SIGNING_* found.');
    print('  Set keys in plug_server/.env (same as Hub deployment) or in plug_agente/.env');
    print('  Try: dart run tool/generate_dev_e2e_signing.dart --write');
    print('  Checked sibling .env paths under monorepo parent.');
    exit(1);
  }

  final agentEnv = loadRepoEnvFile(projectRoot);
  final hubUrl = envValue(agentEnv, 'E2E_HUB_URL');
  final hubTreatAsLocal = envFlag(agentEnv, 'E2E_HUB_IS_LOCAL');
  final allowE2eDevOnRemote = envFlag(agentEnv, 'E2E_HUB_ALLOW_E2E_DEV_ON_REMOTE');

  if (force && !patched && sourceKeyId != null && sourceKey != null) {
    final agentKeyId =
        envValue(agentEnv, 'PAYLOAD_SIGNING_KEY_ID') ?? envValue(agentEnv, 'PAYLOAD_SIGNING_ACTIVE_KEY_ID') ?? '';
    final agentKey = envValue(agentEnv, 'PAYLOAD_SIGNING_KEY') ?? '';
    if (agentKeyId == sourceKeyId && agentKey == sourceKey) {
      print('[skip] plug_agente PAYLOAD_SIGNING_* already matches $sourceEnvPath.');
    } else if (isRemoteHubSigningMismatch(
      hubUrl: hubUrl,
      payloadSigningKeyId: sourceKeyId,
      hubTreatAsLocal: hubTreatAsLocal,
      allowE2eDevOnRemote: allowE2eDevOnRemote,
    )) {
      print(
        '[fail] Sibling PAYLOAD_SIGNING_KEY_ID is e2e-dev while E2E_HUB_URL targets a remote hub — '
        'the monorepo .env is a dev pair. Copy PAYLOAD_SIGNING_* from the deployed Hub .env into plug_agente/.env.',
      );
      exit(1);
    } else {
      print('[skip] plug_agente .env already has PAYLOAD_SIGNING_* (not overwritten).');
    }
  } else if (!patched) {
    print('[skip] plug_agente .env already has PAYLOAD_SIGNING_* (not overwritten).');
  } else {
    print('[ok] Wrote PAYLOAD_SIGNING_KEY_ID and PAYLOAD_SIGNING_KEY to plug_agente/.env');
  }
  print('Next: dart run tool/validate_live_hub_agent_actions_env.dart');
}

Map<String, String> _loadEnvFile(String path) {
  final result = <String, String>{};
  for (final line in File(path).readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#') || !trimmed.contains('=')) {
      continue;
    }
    final idx = trimmed.indexOf('=');
    result[trimmed.substring(0, idx).trim()] = trimmed.substring(idx + 1).trim();
  }
  return result;
}

String? _nonEmpty(Map<String, String> env, String key) {
  final v = env[key]?.trim();
  return v == null || v.isEmpty ? null : v;
}
