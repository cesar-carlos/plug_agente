// ignore_for_file: avoid_print

/// Runs local E2E Hub sync helpers (URL + token [+ optional secure export]) then validate.
///
/// Usage:
///   `dart run tool/sync_e2e_hub_env_from_local.dart`
///   `dart run tool/sync_e2e_hub_env_from_local.dart --export-secure`
library;

import 'dart:io';

import 'src/live_hub_agent_action_env_check.dart';

Future<int> _run(List<String> executableArgs) async {
  final result = await Process.run(
    Platform.executable,
    executableArgs,
    workingDirectory: Directory.current.path,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  return result.exitCode;
}

void main(List<String> args) async {
  final apply = !args.contains('--dry-run');
  final exportSecure = args.contains('--export-secure');
  final forceTokenFlag = args.contains('--force-token');
  final projectRoot = Directory.current.path;
  final fileEnv = loadRepoEnvFile(projectRoot);
  final tokenExpired = liveHubTokenWarnings(envValue(fileEnv, 'E2E_HUB_TOKEN')).isNotEmpty;
  final extra = apply ? <String>['--apply-url', '--apply-agent-id'] : <String>[];
  final tokenExtra = <String>[
    if (apply) '--apply-token',
    if (apply && (forceTokenFlag || tokenExpired)) '--force',
  ];

  print('==> suggest E2E_HUB_URL');
  await _run(<String>['run', 'tool/suggest_e2e_hub_from_local_config.dart', ...extra]);

  print('==> resolve E2E_HUB_TOKEN');
  await _run(<String>['run', 'tool/fetch_e2e_hub_token_from_local_config.dart', ...tokenExtra]);

  if (exportSecure) {
    print('==> export from Windows secure storage (no stdout secrets)');
    await _run(<String>['run', 'tool/export_e2e_secrets_from_local.dart']);
    print('==> promote PAYLOAD_SIGNING_* from monorepo plug_server/.env');
    await _run(<String>['run', 'tool/promote_e2e_signing_from_monorepo_env.dart']);
  }

  print('==> validate live Hub .env');
  final validateCode = await _run(<String>['run', 'tool/validate_live_hub_agent_actions_env.dart']);

  if (validateCode != 0) {
    print('');
    print('Still missing secrets? Steps:');
    print('  1. Open Plug Agente -> Config -> sign in to Hub');
    print('  2. Configure PayloadFrame signing (same keys as Hub server)');
    print('  3. dart run tool/sync_e2e_hub_env_from_local.dart --export-secure');
    print('  Or set E2E_HUB_USERNAME/E2E_HUB_PASSWORD + E2E_HUB_URL/E2E_HUB_AGENT_ID for HTTP login.');
    print('  Or set E2E_HUB_TOKEN, PAYLOAD_SIGNING_KEY_ID, PAYLOAD_SIGNING_KEY in .env manually.');
  }

  exit(validateCode);
}
