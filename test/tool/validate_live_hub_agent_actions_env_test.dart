import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/live_hub_agent_action_env_check.dart';

void main() {
  test('LiveHubAgentActionsEnvOutcome should exit 1 when required keys are missing', () {
    final outcome = LiveHubAgentActionsEnvOutcome.evaluate(<String, String>{});
    expect(outcome.exitCode, 1);
    expect(outcome.missing, isNotEmpty);
    expect(outcome.blocking, isEmpty);
  });

  test('LiveHubAgentActionsEnvOutcome should exit 0 when env is complete and clean', () {
    final farFuture = DateTime.now().toUtc().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    final payload = base64Url.encode(utf8.encode('{"exp":$farFuture}'));
    final token = 'h.$payload.s';

    final outcome = LiveHubAgentActionsEnvOutcome.evaluate(<String, String>{
      'RUN_LIVE_HUB_TESTS': 'true',
      'RUN_LIVE_HUB_SIGNING_TESTS': 'true',
      'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS': 'true',
      'E2E_HUB_URL': 'https://hub.example.com',
      'E2E_HUB_TOKEN': token,
      'PAYLOAD_SIGNING_KEY_ID': 'v1',
      'PAYLOAD_SIGNING_KEY': 'secret',
    });

    expect(outcome.exitCode, 0);
    expect(outcome.missing, isEmpty);
    expect(outcome.blocking, isEmpty);
    expect(outcome.warnings, isEmpty);
  });

  test('LiveHubAgentActionsEnvOutcome should exit 1 on blocking preflight when e2e-dev on remote', () {
    final farFuture = DateTime.now().toUtc().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    final payload = base64Url.encode(utf8.encode('{"exp":$farFuture}'));
    final token = 'h.$payload.s';

    final outcome = LiveHubAgentActionsEnvOutcome.evaluate(<String, String>{
      'RUN_LIVE_HUB_TESTS': 'true',
      'RUN_LIVE_HUB_SIGNING_TESTS': 'true',
      'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS': 'true',
      'E2E_HUB_URL': 'https://hub.example.com',
      'E2E_HUB_TOKEN': token,
      'PAYLOAD_SIGNING_KEY_ID': 'e2e-dev',
      'PAYLOAD_SIGNING_KEY': 'secret',
    });

    expect(outcome.exitCode, 1);
    expect(outcome.missing, isEmpty);
    expect(outcome.blocking, isNotEmpty);
  });

  test('LiveHubAgentActionsEnvOutcome should exit 2 on warnings only when JWT expires soon', () {
    final soon = DateTime.now().toUtc().add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000;
    final payload = base64Url.encode(utf8.encode('{"exp":$soon}'));
    final token = 'h.$payload.s';

    final outcome = LiveHubAgentActionsEnvOutcome.evaluate(<String, String>{
      'RUN_LIVE_HUB_TESTS': 'true',
      'RUN_LIVE_HUB_SIGNING_TESTS': 'true',
      'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS': 'true',
      'E2E_HUB_URL': 'https://hub.example.com',
      'E2E_HUB_TOKEN': token,
      'PAYLOAD_SIGNING_KEY_ID': 'v1',
      'PAYLOAD_SIGNING_KEY': 'secret',
    });

    expect(outcome.exitCode, 2);
    expect(outcome.missing, isEmpty);
    expect(outcome.blocking, isEmpty);
    expect(outcome.warnings, isNotEmpty);
  });

  test('LiveHubAgentActionsEnvOutcome should exit 1 when JWT is expired', () {
    final past = DateTime.now().toUtc().subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
    final payload = base64Url.encode(utf8.encode('{"exp":$past}'));
    final token = 'h.$payload.s';

    final outcome = LiveHubAgentActionsEnvOutcome.evaluate(<String, String>{
      'RUN_LIVE_HUB_TESTS': 'true',
      'RUN_LIVE_HUB_SIGNING_TESTS': 'true',
      'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS': 'true',
      'E2E_HUB_URL': 'https://hub.example.com',
      'E2E_HUB_TOKEN': token,
      'PAYLOAD_SIGNING_KEY_ID': 'v1',
      'PAYLOAD_SIGNING_KEY': 'secret',
    });

    expect(outcome.exitCode, 1);
    expect(outcome.missing, isEmpty);
    expect(outcome.blocking, isNotEmpty);
    expect(outcome.blocking.any((String b) => b.contains('JWT is expired')), isTrue);
  });
}
