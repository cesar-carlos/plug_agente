import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/agent_action_test_manifest.dart';

/// Paths referenced in plano (gate / retencao / RPC) that must stay in the contract manifest.
const List<String> planRequiredAgentActionContractPaths = <String>[
  'test/application/use_cases/notify_agent_action_execution_if_configured_test.dart',
  'test/application/use_cases/cleanup_expired_agent_action_remote_audit_test.dart',
  'test/application/services/agent_action_execution_periodic_purge_test.dart',
  'test/infrastructure/validation/rpc_request_schema_validator_test.dart',
  'test/application/mappers/failure_to_rpc_error_mapper_test.dart',
  'test/application/actions/agent_actions_remote_capability_builder_test.dart',
  'test/infrastructure/external_services/transport/rpc_inbound_handler_test.dart',
  'test/application/use_cases/backfill_agent_action_execution_correlation_test.dart',
  'test/core/constants/agent_action_rpc_constants_test.dart',
  'test/core/config/feature_flags_test.dart',
  'test/docs/openrpc_contract_test.dart',
  'test/application/actions/agent_action_secret_reference_fingerprinter_test.dart',
  'test/infrastructure/actions/agent_action_type_registry_contract_test.dart',
  'test/tool/agent_action_security_gate_checklist_test.dart',
];

void main() {
  final projectRoot = resolvePlugAgenteProjectRoot();

  test('should require flutter_ci homologation gate to read path manifests', () {
    final workflow = File(
      '$projectRoot${Platform.pathSeparator}.github${Platform.pathSeparator}workflows${Platform.pathSeparator}flutter_ci.yml',
    ).readAsStringSync();

    expect(workflow, contains('agent_actions_contract_test_paths.txt'));
    expect(workflow, contains('agent_actions_ui_test_paths.txt'));
  });

  test('should require homologate script to load contract paths from manifest', () {
    final script = File(
      '$projectRoot${Platform.pathSeparator}tool${Platform.pathSeparator}homologate_hub_agent_actions.ps1',
    ).readAsStringSync();

    expect(script, contains('agent_actions_contract_test_paths.txt'));
    expect(script, contains('agent_actions_ui_test_paths.txt'));
    expect(script, contains('Get-ManifestTestPaths'));
  });

  test('should pass RunContractTests switch from operational gate script', () {
    final script = File(
      '$projectRoot${Platform.pathSeparator}tool${Platform.pathSeparator}run_agent_actions_operational_gate.ps1',
    ).readAsStringSync();

    expect(script, contains(r'RunContractTests = $true'));
    expect(script, isNot(contains("@('-RunContractTests')")));
    expect(script, isNot(contains('@("-RunContractTests")')));
  });

  test('should pass homologate switches via hashtable from preflight script', () {
    final script = File(
      '$projectRoot${Platform.pathSeparator}tool${Platform.pathSeparator}preflight_agent_actions_production.ps1',
    ).readAsStringSync();

    expect(script, contains(r"homologateParams['RunContractTests'] = $true"));
    expect(script, contains('@homologateParams'));
    expect(script, isNot(contains('homologateArgs += "-RunContractTests"')));
  });

  test('should not contain duplicate entries in contract manifest', () {
    final paths = readAgentActionContractTestPaths(projectRoot);
    expect(paths.length, paths.toSet().length);
  });

  test('should not contain duplicate entries in UI manifest', () {
    final paths = readAgentActionUiTestPaths(projectRoot);
    expect(paths.length, paths.toSet().length);
  });

  test('should include plan-required contract paths in manifest', () {
    final paths = readAgentActionContractTestPaths(projectRoot).toSet();
    for (final required in planRequiredAgentActionContractPaths) {
      expect(paths, contains(required), reason: 'add $required to agent_actions_contract_test_paths.txt');
    }
  });

  test('should keep live Hub agent.action E2E out of contract manifest', () {
    final paths = readAgentActionContractTestPaths(projectRoot);
    expect(
      paths,
      isNot(contains('test/integration/hub_agent_action_rpc_live_e2e_test.dart')),
    );
  });

  test('should run security gate checklist when homologate RunContractTests is enabled', () {
    final script = File(
      '$projectRoot${Platform.pathSeparator}tool${Platform.pathSeparator}homologate_hub_agent_actions.ps1',
    ).readAsStringSync();

    expect(script, contains('agent_action_security_gate_checklist.dart'));
    expect(script, contains(r'if ($RunContractTests)'));
  });
}
