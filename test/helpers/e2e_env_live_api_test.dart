import 'package:flutter_test/flutter_test.dart';

import 'e2e_env.dart';

void main() {
  setUp(E2EEnv.resetForTesting);

  test('should skip live API tests when env is empty', () async {
    await E2EEnv.loadForTesting('');

    expect(E2EEnv.isLiveApiReady, isFalse);
    expect(E2EEnv.liveApiReadinessSkipMessage, contains('RUN_LIVE_API_TESTS'));
    expect(E2EEnv.apiTestBaseUrlOrNull, isNull);
  });

  test('should skip live API tests when only RUN_LIVE_API_TESTS is set', () async {
    await E2EEnv.loadForTesting('RUN_LIVE_API_TESTS=true');

    expect(E2EEnv.isLiveApiReady, isFalse);
    expect(E2EEnv.liveApiReadinessSkipMessage, contains('API_TEST_BASE_URL'));
    expect(E2EEnv.apiTestBaseUrlOrNull, isNull);
  });

  test('should be ready when RUN_LIVE_API_TESTS and API_TEST_BASE_URL are set', () async {
    await E2EEnv.loadForTesting('''
RUN_LIVE_API_TESTS=true
API_TEST_BASE_URL=http://127.0.0.1:3000/
''');

    expect(E2EEnv.isLiveApiReady, isTrue);
    expect(E2EEnv.liveApiReadinessSkipMessage, isNull);
    expect(E2EEnv.apiTestBaseUrlOrNull, 'http://127.0.0.1:3000/');
  });
}
