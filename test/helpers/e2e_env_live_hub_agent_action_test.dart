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
}
