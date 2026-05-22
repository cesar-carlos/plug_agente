import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/e2e_hub_login_from_env.dart';
import '../../tool/src/e2e_payload_signing_export.dart';
import '../../tool/src/live_hub_agent_action_env_check.dart';

void main() {
  test('should return all required keys when nothing is configured', () {
    expect(
      missingLiveHubAgentActionVariables(
        runLiveHubTests: false,
        runLiveHubSigningTests: false,
        runLiveHubAgentActionRpcTests: false,
        hubUrl: null,
        hubToken: null,
        payloadSigningKeyId: null,
        payloadSigningKey: null,
      ),
      hasLength(7),
    );
  });

  test('should return empty when all required values are present', () {
    expect(
      missingLiveHubAgentActionVariables(
        runLiveHubTests: true,
        runLiveHubSigningTests: true,
        runLiveHubAgentActionRpcTests: true,
        hubUrl: 'https://hub.example.com',
        hubToken: 'token',
        payloadSigningKeyId: 'v1',
        payloadSigningKey: 'secret',
      ),
      isEmpty,
    );
  });

  test('should list RUN_LIVE_HUB_TESTS when flag is explicitly false', () {
    final fileEnv = <String, String>{'RUN_LIVE_HUB_TESTS': 'false'};

    expect(missingFromRepoEnv(fileEnv), contains('RUN_LIVE_HUB_TESTS'));
    expect(envFlagExplicitlyFalse(fileEnv, 'RUN_LIVE_HUB_TESTS'), isTrue);
  });

  test('should detect commented hub keys in dotenv file', () {
    final dir = Directory.systemTemp.createTempSync('plug_agente_env_check_');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    File('${dir.path}${Platform.pathSeparator}.env').writeAsStringSync('''
# RUN_LIVE_HUB_TESTS=true
# E2E_HUB_URL=https://hub.example.com
ODBC_TEST_DSN=x
''');

    expect(
      commentedHubKeysInDotEnv(dir.path),
      containsAll(<String>['RUN_LIVE_HUB_TESTS', 'E2E_HUB_URL']),
    );
  });

  test('should preserve quoted dotenv values when loading repo env file', () {
    final dir = Directory.systemTemp.createTempSync('plug_agente_env_quotes_');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    File('${dir.path}${Platform.pathSeparator}.env').writeAsStringSync('''
E2E_HUB_URL="https://hub.example.com/agents"
E2E_HUB_TOKEN='token-123'
''');

    final fileEnv = loadRepoEnvFile(dir.path);

    expect(fileEnv['E2E_HUB_URL'], 'https://hub.example.com/agents');
    expect(fileEnv['E2E_HUB_TOKEN'], 'token-123');
  });

  test('should read signing from payload_signing_keys_json secure storage shape', () {
    final candidate = readPayloadSigningFromSecureStorageMap(<String, String>{
      'payload_signing_keys_json': '{"v1":"secret-hmac"}',
      'payload_signing_active_key_id': 'v1',
    });
    expect(candidate, isNotNull);
    expect(candidate!.keyId, 'v1');
    expect(candidate.secret, 'secret-hmac');
  });

  test('should warn when e2e-dev signing is used against a remote hub url', () {
    expect(
      liveHubEnvWarnings(
        hubUrl: 'https://plug-server.example.com/agents',
        payloadSigningKeyId: 'e2e-dev',
      ),
      isNotEmpty,
    );
    expect(
      liveHubEnvWarnings(
        hubUrl: 'http://127.0.0.1:3000/agents',
        payloadSigningKeyId: 'e2e-dev',
      ),
      isEmpty,
    );
  });

  test('should read E2E hub login credentials from env map', () {
    final login = readE2eHubLoginFromEnvMap(<String, String>{
      'E2E_HUB_URL': 'https://hub.example.com/agents',
      'E2E_HUB_AGENT_ID': 'agent-1',
      'E2E_HUB_USERNAME': 'e2e-user',
      'E2E_HUB_PASSWORD': 'secret',
    });

    expect(login, isNotNull);
    expect(login!.serverUrl, 'https://hub.example.com');
    expect(login.agentId, 'agent-1');
    expect(login.username, 'e2e-user');
  });

  test('should warn when E2E hub JWT is expired', () {
    final expiredPayload = base64Url.encode(utf8.encode('{"exp":1}'));
    final token = 'header.$expiredPayload.signature';

    expect(liveHubTokenWarnings(token), isNotEmpty);
    expect(
      liveHubEnvWarnings(hubUrl: 'https://hub.example.com', payloadSigningKeyId: 'v1', hubToken: token),
      isNotEmpty,
    );
  });

  test('should block live hub preflight for expired JWT before socket connect', () {
    final expiredPayload = base64Url.encode(utf8.encode('{"exp":1}'));
    final token = 'header.$expiredPayload.signature';

    expect(
      blockingLiveHubEnvFailures(
        runLiveHubTests: true,
        hubUrl: 'https://hub.example.com/agents',
        hubToken: token,
        payloadSigningKeyId: 'v1',
      ),
      isNotEmpty,
    );
  });

  test('should not block live hub preflight when JWT expires soon but is still valid', () {
    final soon = DateTime.now().toUtc().add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000;
    final payload = base64Url.encode(utf8.encode('{"exp":$soon}'));
    final token = 'header.$payload.signature';

    expect(liveHubTokenWarnings(token), isNotEmpty);
    expect(
      blockingLiveHubEnvFailures(
        runLiveHubTests: true,
        hubUrl: 'https://hub.example.com/agents',
        hubToken: token,
        payloadSigningKeyId: 'v1',
      ),
      isEmpty,
    );
  });

  test('should block e2e-dev signing only when signing key id is provided for remote hub', () {
    final farFuture = DateTime.now().toUtc().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    final payload = base64Url.encode(utf8.encode('{"exp":$farFuture}'));
    final token = 'header.$payload.signature';

    expect(
      blockingLiveHubEnvFailures(
        runLiveHubTests: true,
        hubUrl: 'https://hub.example.com/agents',
        hubToken: token,
      ),
      isEmpty,
    );
    expect(
      blockingLiveHubEnvFailures(
        runLiveHubTests: true,
        hubUrl: 'https://hub.example.com/agents',
        hubToken: token,
        payloadSigningKeyId: 'e2e-dev',
      ),
      isNotEmpty,
    );
  });

  test('should not block live hub preflight when live flag is disabled', () {
    final expiredPayload = base64Url.encode(utf8.encode('{"exp":1}'));
    final token = 'header.$expiredPayload.signature';

    expect(
      blockingLiveHubEnvFailures(
        runLiveHubTests: false,
        hubUrl: 'https://hub.example.com/agents',
        hubToken: token,
        payloadSigningKeyId: 'v1',
      ),
      isEmpty,
    );
  });

  test('should not warn when E2E hub JWT expiry is far in the future', () {
    final farFuture = DateTime.now().toUtc().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    final payload = base64Url.encode(utf8.encode('{"exp":$farFuture}'));
    final token = 'header.$payload.signature';

    expect(liveHubTokenWarnings(token), isEmpty);
  });

  test('should accept PAYLOAD_SIGNING_ACTIVE_KEY_ID as signing key id', () {
    final fileEnv = <String, String>{
      'RUN_LIVE_HUB_TESTS': 'true',
      'RUN_LIVE_HUB_SIGNING_TESTS': 'true',
      'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS': 'true',
      'E2E_HUB_URL': 'https://hub.example.com',
      'E2E_HUB_TOKEN': 'token',
      'PAYLOAD_SIGNING_ACTIVE_KEY_ID': 'v1',
      'PAYLOAD_SIGNING_KEY': 'secret',
    };

    expect(missingFromRepoEnv(fileEnv), isEmpty);
  });
}
