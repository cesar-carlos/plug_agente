// ignore_for_file: avoid_print

/// Validates `.env` / process environment for live Hub `agent.action.*` tests.
///
/// Usage: `dart run tool/validate_live_hub_agent_actions_env.dart`
///
/// Exit codes: `0` = ready; `1` = missing variables or blocking preflight; `2` = warnings only.
library;

import 'dart:io';

import 'src/live_hub_agent_action_env_check.dart';

void _printFlagRow(Map<String, String> fileEnv, String key) {
  final label = '$key=true';
  if (envFlag(fileEnv, key)) {
    print('  [ok] $label');
    return;
  }
  if (envFlagExplicitlyFalse(fileEnv, key)) {
    print('  [ ] $label (currently false — change to true in .env)');
    return;
  }
  print('  [ ] $label');
}

void _printValueRow(Map<String, String> fileEnv, String label, bool ok) {
  if (ok) {
    print('  [ok] $label');
    return;
  }
  if (label.contains(' or ')) {
    final hasId =
        fileEnv.containsKey('PAYLOAD_SIGNING_KEY_ID') ||
        fileEnv.containsKey('PAYLOAD_SIGNING_ACTIVE_KEY_ID') ||
        Platform.environment.containsKey('PAYLOAD_SIGNING_KEY_ID') ||
        Platform.environment.containsKey('PAYLOAD_SIGNING_ACTIVE_KEY_ID');
    if (!hasId) {
      print('  [ ] $label');
      return;
    }
    print('  [ ] $label (empty in .env)');
    return;
  }
  if (fileEnv.containsKey(label) || Platform.environment.containsKey(label)) {
    print('  [ ] $label (empty in .env)');
    return;
  }
  print('  [ ] $label');
}

void _printChecklist(Map<String, String> fileEnv) {
  print('Live Hub agent.action checklist (.env or process env):');
  _printFlagRow(fileEnv, 'RUN_LIVE_HUB_TESTS');
  _printFlagRow(fileEnv, 'RUN_LIVE_HUB_SIGNING_TESTS');
  _printFlagRow(fileEnv, 'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS');
  _printValueRow(fileEnv, 'E2E_HUB_URL', _hasValue(envValue(fileEnv, 'E2E_HUB_URL')));
  _printValueRow(fileEnv, 'E2E_HUB_TOKEN', _hasValue(envValue(fileEnv, 'E2E_HUB_TOKEN')));
  _printValueRow(
    fileEnv,
    'PAYLOAD_SIGNING_KEY_ID or PAYLOAD_SIGNING_ACTIVE_KEY_ID',
    _hasValue(envValue(fileEnv, 'PAYLOAD_SIGNING_KEY_ID')) ||
        _hasValue(envValue(fileEnv, 'PAYLOAD_SIGNING_ACTIVE_KEY_ID')),
  );
  _printValueRow(fileEnv, 'PAYLOAD_SIGNING_KEY', _hasValue(envValue(fileEnv, 'PAYLOAD_SIGNING_KEY')));
}

bool _hasValue(String? value) => value != null && value.trim().isNotEmpty;

void _printFixHints() {
  print('  Fix signing: copy PAYLOAD_SIGNING_* from the deployed Hub .env (not e2e-dev for production).');
  print('        dart run tool/export_e2e_secrets_from_local.dart');
  print('        dart run tool/promote_e2e_signing_from_monorepo_env.dart');
  print('  Fix token:   dart run tool/fetch_e2e_hub_token_from_local_config.dart --apply-token --force');
}

void main() {
  final root = projectRootFromScript();
  final fileEnv = loadRepoEnvFile(root);
  _printChecklist(fileEnv);

  final outcome = LiveHubAgentActionsEnvOutcome.evaluate(fileEnv);

  if (outcome.exitCode == 1 && outcome.missing.isNotEmpty) {
    print('');
    print('[fail] Missing: ${outcome.missing.join(', ')}');
    final envPath = '$root${Platform.pathSeparator}.env';
    if (File(envPath).existsSync()) {
      print('  .env found at $envPath');
      final commented = commentedHubKeysInDotEnv(root);
      if (commented.isNotEmpty) {
        print(
          '  Hint: these keys are commented out (remove leading #): ${commented.join(', ')}',
        );
      }
    } else {
      print('  Copy .env.example to .env and fill Hub agent.action.* variables.');
    }
    print('  See docs/testing/e2e_setup.md (Hub agent.action.*).');
    final onlySigning = outcome.missing.every(
      (String name) => name.contains('PAYLOAD_SIGNING'),
    );
    if (onlySigning) {
      print('  Hint: same HMAC key id + secret as the Hub (plug_server/.env).');
      print('        dart run tool/promote_e2e_signing_from_monorepo_env.dart');
      print('        dart run tool/export_e2e_secrets_from_local.dart  (Config → WebSocket signing)');
      print('        Or paste PAYLOAD_SIGNING_KEY_ID and PAYLOAD_SIGNING_KEY into plug_agente/.env');
      print('        Or: dart run tool/generate_dev_e2e_signing.dart --write  (dev only; mirror to plug_server/.env)');
    } else {
      print('  Hint: dart run tool/sync_e2e_hub_env_from_local.dart --export-secure');
    }
    exit(1);
  }

  if (outcome.exitCode == 1 && outcome.blocking.isNotEmpty) {
    print('');
    print('Blocking live Hub preflight (tests will fail before Socket.IO):');
    for (final line in outcome.blocking) {
      print('  [fail] $line');
    }
    if (outcome.warnings.isNotEmpty) {
      print('');
      print('Additional hints:');
      for (final line in outcome.warnings) {
        if (outcome.blocking.contains(line)) {
          continue;
        }
        print('  [warn] $line');
      }
    }
    print('');
    _printFixHints();
    exit(1);
  }

  if (outcome.exitCode == 2) {
    print('');
    print('Warnings (live tests may fail):');
    for (final warning in outcome.warnings) {
      print('  [warn] $warning');
    }
    print('');
    _printFixHints();
    exit(2);
  }

  print('');
  print('[ok] Live Hub agent.action environment is ready.');
  print('  Probe: flutter test test/integration/hub_socket_live_e2e_test.dart --name "signed PayloadFrame"');
  print(r'  Run: .\tool\homologate_hub_agent_actions.ps1 -RunLiveTests');
  print('  Or:  flutter test test/integration/hub_agent_action_rpc_live_e2e_test.dart --tags live');
  exit(0);
}
