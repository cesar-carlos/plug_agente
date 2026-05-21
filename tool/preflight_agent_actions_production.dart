// ignore_for_file: avoid_print

/// Production-readiness preflight for agent actions (static checks only).
///
/// Usage:
///   dart run tool/preflight_agent_actions_production.dart
///   dart run tool/preflight_agent_actions_production.dart --strict-com
library;

import 'dart:io';

import 'src/agent_action_production_preflight.dart';
import 'src/live_hub_agent_action_env_check.dart';

void _printRows(String tag, List<String> rows) {
  for (final row in rows) {
    print('  [$tag] $row');
  }
}

Future<void> main(List<String> args) async {
  final strictCom = args.contains('--strict-com');
  final root = projectRootFromScript();
  final fileEnv = loadRepoEnvFile(root);
  final comSource = readComObjectProductionRegistrationsSource(root);

  print('Agent actions production preflight (plug_agente)');
  print('Repo: $root');
  print('');

  final result = evaluateAgentActionProductionPreflight(
    comRegistrationsSource: comSource,
    fileEnv: fileEnv,
    projectRoot: root,
    strictComHandlers: strictCom,
  );

  _printRows('ok', result.ok);
  _printRows('warn', result.warnings);
  _printRows('fail', result.failures);

  print('');
  print('Manual (see plano — Riscos aceitos RA-01..RA-08):');
  print('  - Threat model PR review before enabling remote/elevated/ad-hoc per type.');
  print('  - Hub: allowlist and rate limit on consumer (cross-repo).');
  print('  - Rollback: FeatureFlags.disableAgentActionsRemoteRollout() → maintenance → disable subsystem.');
  print('');
  print('Next commands:');
  print('  dart run tool/agent_action_security_gate_checklist.dart [actionType]');
  print(r'  .\tool\homologate_hub_agent_actions.ps1 -RunContractTests');
  print(r'  .\tool\homologate_hub_agent_actions.ps1 -PrepareLiveEnv -ValidateLiveEnv -RunLiveTests');

  if (!result.isSuccess) {
    exit(1);
  }
}
