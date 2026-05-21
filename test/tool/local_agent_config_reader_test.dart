import 'package:test/test.dart';

import '../../tool/src/local_agent_config_reader.dart';

void main() {
  test('readHubSecretsFromStorageMap should resolve hub auth secrets by config id', () {
    final secrets = readHubSecretsFromStorageMap(
      'cfg-1',
      <String, String>{
        'hub_auth_secret_cfg-1_auth_token': ' token-123 ',
        'hub_auth_secret_cfg-1_refresh_token': ' refresh-123 ',
        'hub_auth_secret_cfg-1_auth_password': ' password-123 ',
        'hub_auth_secret_other_auth_token': 'ignore-me',
      },
    );

    expect(secrets.authToken, 'token-123');
    expect(secrets.refreshToken, 'refresh-123');
    expect(secrets.authPassword, 'password-123');
  });

  test('mergeLocalHubConfigWithSecureStorageMap should fill missing token and password', () {
    final merged = mergeLocalHubConfigWithSecureStorageMap(
      const LocalAgentHubConfig(
        configId: 'cfg-1',
        serverUrl: 'https://hub.example.com',
        agentId: 'agent-1',
        authUsername: 'operator',
      ),
      <String, String>{
        'hub_auth_secret_cfg-1_auth_token': 'token-123',
        'hub_auth_secret_cfg-1_refresh_token': 'refresh-123',
        'hub_auth_secret_cfg-1_auth_password': 'password-123',
      },
    );

    expect(merged.authUsername, 'operator');
    expect(merged.authToken, 'token-123');
    expect(merged.refreshToken, 'refresh-123');
    expect(merged.authPassword, 'password-123');
  });

  test('mergeLocalHubConfigWithSecureStorageMap should keep non-empty config values', () {
    final merged = mergeLocalHubConfigWithSecureStorageMap(
      const LocalAgentHubConfig(
        configId: 'cfg-1',
        serverUrl: 'https://hub.example.com',
        agentId: 'agent-1',
        authToken: 'db-token',
        refreshToken: 'db-refresh',
        authUsername: 'operator',
        authPassword: 'db-password',
      ),
      <String, String>{
        'hub_auth_secret_cfg-1_auth_token': 'token-123',
        'hub_auth_secret_cfg-1_refresh_token': 'refresh-123',
        'hub_auth_secret_cfg-1_auth_password': 'password-123',
      },
    );

    expect(merged.authToken, 'db-token');
    expect(merged.refreshToken, 'db-refresh');
    expect(merged.authPassword, 'db-password');
  });
}
