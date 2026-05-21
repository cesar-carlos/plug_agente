// ignore_for_file: avoid_print

/// PR security gate checklist for agent action types.
library;

const List<String> agentActionSecurityGateMvpTypes = <String>[
  'commandLine',
  'executable',
  'script',
  'jar',
  'email',
  'comObject',
  'developer',
];

const Map<String, String> agentActionThreatModelSummaryByType = <String, String>{
  'commandLine':
      'Shell/cmd; injection + stdout leak — normalizer, allowlist, capturePolicy, redactor.',
  'executable': 'CreateProcess; binary swap — path snapshot/hash, allowlist.',
  'script': 'Interpreter + script; hijack — path validation, encoding policy.',
  'jar': 'java + JAR — path/Java preflight.',
  'email':
      'SMTP/attachments — secure storage, path validation on attachments; re-approve remote after secret rotation.',
  'comObject':
      'COM ProgId — production handlers in com_object_production_registrations.dart (stub only for homologation).',
  'developer':
      'Data7 XML — catalog id/label only, no password in hash; no remote config override.',
};

/// Resolves action types from CLI [args] or returns all MVP types when empty.
List<String> resolveSecurityGateActionTypes(List<String> args) {
  final requested = args.where((String a) => a.isNotEmpty && !a.startsWith('-')).toList();
  return requested.isEmpty ? agentActionSecurityGateMvpTypes : requested;
}

String? threatModelSummaryFor(String actionType) =>
    agentActionThreatModelSummaryByType[actionType];

void printAgentActionSecurityGateChecklist(List<String> types) {
  print('Agent action security gate — PR checklist (plug_agente)');
  print('');
  print('Before enabling remote, elevated, or ad-hoc for a type:');
  print('  1. Review threat model row in docs/implemente/plano_acoes_agendadas_execucoes.md');
  print('     (section "Threat model baseline por adapter").');
  print(r'  2. Run: .\tool\run_agent_actions_operational_gate.ps1');
  print(r'     (or .\tool\homologate_hub_agent_actions.ps1 -RunContractTests)');
  print('  3. If wire/capabilities change: update OpenRPC + docs/communication/schemas');
  print('     in the same PR; gate includes test/docs/openrpc_contract_test.dart.');
  print('  4. Confirm FeatureFlags defaults stay safe; document rollback (gate §4195).');
  print('  5. Record accepted risk in plan "Riscos aceitos" if something stays open.');
  print('');

  for (final type in types) {
    final summary = threatModelSummaryFor(type);
    print('--- $type ---');
    if (summary == null) {
      print('  [warn] Unknown type; add to threat model table before production remote.');
      continue;
    }
    print('  $summary');
    print('  [ ] Human threat-model sign-off for remote/elevated/ad-hoc');
    print('  [ ] Contract gate green for touched adapters/runners');
    if (type == 'comObject') {
      print('  [ ] Production COM handler registered OR explicit RA-01 stub documented');
    }
    if (type == 'developer') {
      print('  [ ] Field homologation completed if enabling remote in production');
    }
    print('');
  }

  print('Hub-side (cross-repo): allowlist + rate limit on consumer before production rollout.');
}

void main(List<String> args) {
  printAgentActionSecurityGateChecklist(resolveSecurityGateActionTypes(args));
}
