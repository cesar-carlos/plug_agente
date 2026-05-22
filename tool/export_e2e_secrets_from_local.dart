// ignore_for_file: avoid_print

/// Exports Hub token and PayloadFrame signing keys into `.env` from Windows storage.
///
/// Usage:
///   `dart run tool/export_e2e_secrets_from_local.dart`
///   `dart run tool/export_e2e_secrets_from_local.dart --force`
library;

import 'dart:io';

import 'src/dot_env_patch.dart';
import 'src/e2e_payload_signing_export.dart';
import 'src/live_hub_agent_action_env_check.dart';
import 'src/local_agent_config_reader.dart';
import 'src/plug_agente_windows_secure_storage_reader.dart';

void main(List<String> args) {
  final force = args.contains('--force');
  if (!Platform.isWindows) {
    print('[warn] Windows only (Plug Agente secure storage path).');
    exit(1);
  }

  final projectRoot = Directory.current.path;
  final config = readLatestLocalAgentHubConfig();
  if (config == null) {
    print('[info] No agent_config.db / config row.');
    exit(1);
  }

  final storagePath = plugAgenteSecureStorageFilePath();
  if (storagePath == null || !File(storagePath).existsSync()) {
    print('[info] Secure storage file not found.');
    print(r'  Expected: %APPDATA%\com.se7esistemas\plug_agente\flutter_secure_storage.dat');
    print('  Run plug_agente.exe, sign in via Config, configure signing, then retry.');
    exit(1);
  }

  print('[ok] Reading secure storage (values not printed).');
  final Map<String, String> map;
  try {
    map = readPlugAgenteWindowsSecureStorage();
  } on Object catch (error) {
    print('[fail] Could not decrypt secure storage: $error');
    exit(1);
  }

  var patched = false;
  final fileEnv = loadRepoEnvFile(projectRoot);
  final replaceToken = force || liveHubTokenWarnings(envValue(fileEnv, 'E2E_HUB_TOKEN')).isNotEmpty;
  final hubUrl = envValue(fileEnv, 'E2E_HUB_URL');
  final currentSigningKeyId =
      envValue(fileEnv, 'PAYLOAD_SIGNING_KEY_ID') ?? envValue(fileEnv, 'PAYLOAD_SIGNING_ACTIVE_KEY_ID');
  final hubTreatAsLocal = envFlag(fileEnv, 'E2E_HUB_IS_LOCAL');
  final allowE2eDevOnRemote = envFlag(fileEnv, 'E2E_HUB_ALLOW_E2E_DEV_ON_REMOTE');

  final hubTokenKey = 'hub_auth_secret_${config.configId}_auth_token';
  final hubToken = map[hubTokenKey]?.trim();
  if (hubToken != null && hubToken.isNotEmpty) {
    patched =
        patchDotEnvKey(
          projectRoot: projectRoot,
          key: 'E2E_HUB_TOKEN',
          value: hubToken,
          onlyIfEmpty: !replaceToken,
        ) ||
        patched;
    print('[ok] E2E_HUB_TOKEN ${dotEnvKeyIsEmpty(projectRoot, 'E2E_HUB_TOKEN') ? "patched" : "already set"}');
  } else {
    print('[ ] E2E_HUB_TOKEN not in secure storage ($hubTokenKey)');
  }

  final signing = readPayloadSigningFromSecureStorageMap(map);
  if (signing != null) {
    final replaceSigning =
        force ||
        isRemoteHubSigningMismatch(
          hubUrl: hubUrl,
          payloadSigningKeyId: currentSigningKeyId,
          hubTreatAsLocal: hubTreatAsLocal,
          allowE2eDevOnRemote: allowE2eDevOnRemote,
        ) ||
        (currentSigningKeyId != null &&
            currentSigningKeyId.trim().isNotEmpty &&
            signing.keyId.trim() != currentSigningKeyId.trim());
    final signingOnlyIfEmpty = !replaceSigning;
    var signingChanged = false;
    signingChanged =
        patchDotEnvKey(
          projectRoot: projectRoot,
          key: 'PAYLOAD_SIGNING_KEY_ID',
          value: signing.keyId,
          onlyIfEmpty: signingOnlyIfEmpty,
        ) ||
        signingChanged;
    signingChanged =
        patchDotEnvKey(
          projectRoot: projectRoot,
          key: 'PAYLOAD_SIGNING_KEY',
          value: signing.secret,
          onlyIfEmpty: signingOnlyIfEmpty,
        ) ||
        signingChanged;
    if (signing.activeKeyId != null && signing.activeKeyId!.isNotEmpty && signing.activeKeyId != signing.keyId) {
      signingChanged =
          patchDotEnvKey(
            projectRoot: projectRoot,
            key: 'PAYLOAD_SIGNING_ACTIVE_KEY_ID',
            value: signing.activeKeyId!,
            onlyIfEmpty: signingOnlyIfEmpty,
          ) ||
          signingChanged;
    }
    patched = patched || signingChanged;
    if (signingChanged) {
      print('[ok] PAYLOAD_SIGNING_* patched from secure storage');
    } else if (replaceSigning) {
      print('[skip] PAYLOAD_SIGNING_* unchanged (already matches secure storage values)');
    } else {
      print('[skip] PAYLOAD_SIGNING_* unchanged (use --force to overwrite)');
    }
  } else {
    print('[ ] payload signing keys not in secure storage');
    final related = listPayloadSigningRelatedStorageKeys(map);
    if (related.isNotEmpty) {
      print('  Found related storage keys (values not shown): ${related.join(", ")}');
    }
    print('  Configure PayloadFrame signing in Config → WebSocket (enable signing + key id/secret).');
    print('  Or copy PAYLOAD_SIGNING_KEY_ID and PAYLOAD_SIGNING_KEY from the Hub server .env.');
    print('  Then: dart run tool/promote_e2e_signing_from_monorepo_env.dart');
  }

  final tokenReady = !dotEnvKeyIsEmpty(projectRoot, 'E2E_HUB_TOKEN');
  final signingReady =
      !dotEnvKeyIsEmpty(projectRoot, 'PAYLOAD_SIGNING_KEY_ID') ||
      !dotEnvKeyIsEmpty(projectRoot, 'PAYLOAD_SIGNING_ACTIVE_KEY_ID');
  final signingKeyReady = !dotEnvKeyIsEmpty(projectRoot, 'PAYLOAD_SIGNING_KEY');

  if (tokenReady && signingReady && signingKeyReady) {
    print('Next: dart run tool/validate_live_hub_agent_actions_env.dart');
    exit(0);
  }

  if (!tokenReady) {
    print('[info] E2E_HUB_TOKEN still empty. Sign in via Config in plug_agente.exe first.');
    exit(1);
  }

  print('[info] E2E_HUB_TOKEN ok; PAYLOAD_SIGNING_* still needed (see hints above).');
  exit(1);
}
