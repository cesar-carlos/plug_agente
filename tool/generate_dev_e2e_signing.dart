// ignore_for_file: avoid_print

/// Generates a development HMAC signing pair for live Hub E2E (same id + secret on Hub).
///
/// Usage:
///   dart run tool/generate_dev_e2e_signing.dart
///   dart run tool/generate_dev_e2e_signing.dart --write
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'src/dot_env_patch.dart';
import 'src/e2e_monorepo_env_paths.dart';
import 'src/live_hub_agent_action_env_check.dart';

bool _patchSigningPair({
  required String projectRoot,
  required String keyId,
  required String secret,
}) {
  final idChanged = patchDotEnvKey(
    projectRoot: projectRoot,
    key: 'PAYLOAD_SIGNING_KEY_ID',
    value: keyId,
  );
  final keyChanged = patchDotEnvKey(
    projectRoot: projectRoot,
    key: 'PAYLOAD_SIGNING_KEY',
    value: secret,
  );
  return idChanged || keyChanged;
}

String _envFileRoot(String envFilePath) {
  return File(envFilePath).parent.path;
}

void main(List<String> args) {
  final write = args.contains('--write');
  final root = projectRootFromScript();
  const keyId = 'e2e-dev';
  final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
  final key = base64Url.encode(bytes);

  print('Development PayloadFrame signing (same id + secret on agent and Hub):');
  print('PAYLOAD_SIGNING_KEY_ID=$keyId');
  print('PAYLOAD_SIGNING_KEY=$key');
  print('');

  if (!write) {
    print('To write empty keys: dart run tool/generate_dev_e2e_signing.dart --write');
    print('Then: dart run tool/validate_live_hub_agent_actions_env.dart');
    return;
  }

  var anyChanged = false;
  if (_patchSigningPair(projectRoot: root, keyId: keyId, secret: key)) {
    print('[ok] Updated plug_agente/.env (only empty signing keys were replaced).');
    anyChanged = true;
  } else {
    print('[skip] plug_agente/.env already has signing values.');
  }

  var hubEnvFiles = siblingHubEnvFileCandidates(root);
  if (hubEnvFiles.isEmpty) {
    for (final hubRoot in siblingHubProjectRoots(root)) {
      if (!Directory(hubRoot).existsSync()) {
        continue;
      }
      final envPath = '$hubRoot${Platform.pathSeparator}.env';
      if (File(envPath).existsSync()) {
        continue;
      }
      File(envPath).writeAsStringSync(
        'PAYLOAD_SIGNING_KEY_ID=$keyId\nPAYLOAD_SIGNING_KEY=$key\n',
      );
      print('[ok] Created $envPath with dev signing keys.');
      anyChanged = true;
      hubEnvFiles = siblingHubEnvFileCandidates(root);
      break;
    }
  }
  if (hubEnvFiles.isEmpty) {
    print('[info] No sibling plug_server/.env found — paste the lines above into the Hub .env.');
  } else {
    for (final envPath in hubEnvFiles) {
      final hubRoot = _envFileRoot(envPath);
      if (_patchSigningPair(projectRoot: hubRoot, keyId: keyId, secret: key)) {
        print('[ok] Updated $envPath (only empty signing keys were replaced).');
        anyChanged = true;
      } else {
        print('[skip] $envPath already has signing values.');
      }
    }
  }

  if (!anyChanged) {
    print('[hint] Clear PAYLOAD_SIGNING_* in .env files or edit manually, then re-run --write.');
  }
  print('Restart Hub and agent after changes.');
  print('Next: dart run tool/validate_live_hub_agent_actions_env.dart');
}
