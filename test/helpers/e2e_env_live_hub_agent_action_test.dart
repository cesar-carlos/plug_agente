import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'e2e_env.dart';

void main() {
  setUp(E2EEnv.resetForTesting);

  test('should list all missing live hub agent action variables when env is empty', () async {
    await E2EEnv.loadForTesting('');

    expect(E2EEnv.isLiveHubAgentActionReady, isFalse);
    expect(
      E2EEnv.missingLiveHubAgentActionVariableNames,
      containsAll(<String>[
        'RUN_LIVE_HUB_TESTS',
        'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS',
        'RUN_LIVE_HUB_SIGNING_TESTS',
        'E2E_HUB_URL',
        'E2E_HUB_TOKEN',
        'PAYLOAD_SIGNING_KEY',
      ]),
    );
    expect(E2EEnv.liveHubAgentActionReadinessSkipMessage, isNotNull);
  });

  test('should be ready when required live hub agent action variables are set', () async {
    await E2EEnv.loadForTesting('''
RUN_LIVE_HUB_TESTS=true
RUN_LIVE_HUB_SIGNING_TESTS=true
RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS=true
E2E_HUB_URL=https://hub.example.com
E2E_HUB_TOKEN=token
PAYLOAD_SIGNING_KEY_ID=v1
PAYLOAD_SIGNING_KEY=secret
''');

    expect(E2EEnv.missingLiveHubAgentActionVariableNames, isEmpty);
    expect(E2EEnv.isLiveHubAgentActionReady, isTrue);
    expect(E2EEnv.liveHubAgentActionReadinessSkipMessage, isNull);
  });

  test('should not report signing mismatch blocking when E2E_HUB_ALLOW_E2E_DEV_ON_REMOTE is true', () async {
    final farFuture = DateTime.now().toUtc().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    final payload = base64Url.encode(utf8.encode('{"exp":$farFuture}'));
    final token = 'h.$payload.s';

    await E2EEnv.loadForTesting('''
RUN_LIVE_HUB_TESTS=true
RUN_LIVE_HUB_SIGNING_TESTS=true
E2E_HUB_URL=https://remote.example.com
E2E_HUB_TOKEN=$token
PAYLOAD_SIGNING_KEY_ID=e2e-dev
PAYLOAD_SIGNING_KEY=secret
E2E_HUB_ALLOW_E2E_DEV_ON_REMOTE=true
''');

    expect(E2EEnv.liveHubBlockingPreflightFailureMessage(requireSigning: true), isNull);
  });

  test('should not report signing mismatch blocking when E2E_HUB_IS_LOCAL is true', () async {
    final farFuture = DateTime.now().toUtc().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    final payload = base64Url.encode(utf8.encode('{"exp":$farFuture}'));
    final token = 'h.$payload.s';

    await E2EEnv.loadForTesting('''
RUN_LIVE_HUB_TESTS=true
RUN_LIVE_HUB_SIGNING_TESTS=true
E2E_HUB_URL=https://staging-lan.example.com
E2E_HUB_TOKEN=$token
PAYLOAD_SIGNING_KEY_ID=e2e-dev
PAYLOAD_SIGNING_KEY=secret
E2E_HUB_IS_LOCAL=true
''');

    expect(E2EEnv.liveHubBlockingPreflightFailureMessage(requireSigning: true), isNull);
  });

  test('should skip live hub agent action tests when E2E hub JWT is expired', () async {
    final expired = DateTime.now().toUtc().subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
    final payload = base64Url.encode(utf8.encode('{"exp":$expired}'));
    final token = 'h.$payload.s';

    await E2EEnv.loadForTesting('''
RUN_LIVE_HUB_TESTS=true
RUN_LIVE_HUB_SIGNING_TESTS=true
RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS=true
E2E_HUB_URL=https://hub.example.com
E2E_HUB_TOKEN=$token
PAYLOAD_SIGNING_KEY_ID=v1
PAYLOAD_SIGNING_KEY=secret
''');

    expect(E2EEnv.isLiveHubAgentActionReady, isFalse);
    expect(E2EEnv.liveHubAgentActionReadinessSkipMessage, contains('JWT is expired'));
  });
}
