/// Reads latest WebSocket config row from PlugAgente `agent_config.db`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'hub_url_for_e2e.dart';
import 'plug_agente_windows_secure_storage_reader.dart';

export 'hub_url_for_e2e.dart' show ensureAgentsNamespaceUrl, isPlaceholderServerUrl;

List<String> plugAgenteStorageCandidates() {
  final candidates = <String>[];
  final seen = <String>{};

  void add(String? value) {
    if (value == null || value.isEmpty) {
      return;
    }
    final normalized = p.normalize(value);
    if (seen.add(normalized)) {
      candidates.add(normalized);
    }
  }

  const folder = 'PlugAgente';
  add(
    Platform.environment['ProgramData'] == null ? null : p.join(Platform.environment['ProgramData']!, folder),
  );
  add(
    Platform.environment['ALLUSERSPROFILE'] == null ? null : p.join(Platform.environment['ALLUSERSPROFILE']!, folder),
  );
  add(
    Platform.environment['PUBLIC'] == null ? null : p.join(Platform.environment['PUBLIC']!, 'Documents', folder),
  );
  add(p.join(r'C:\ProgramData', folder));
  return candidates;
}

String? findAgentConfigDatabasePath() {
  for (final root in plugAgenteStorageCandidates()) {
    final dbPath = p.join(root, 'agent_config.db');
    if (File(dbPath).existsSync()) {
      return dbPath;
    }
  }
  return null;
}

class LocalAgentHubConfig {
  const LocalAgentHubConfig({
    required this.configId,
    required this.serverUrl,
    required this.agentId,
    this.authToken,
    this.refreshToken,
    this.authUsername,
    this.authPassword,
  });

  final String configId;
  final String serverUrl;
  final String agentId;
  final String? authToken;
  final String? refreshToken;
  final String? authUsername;
  final String? authPassword;

  bool get hasAuthTokenInDb => authToken != null && authToken!.trim().isNotEmpty;

  bool get hasStoredCredentials {
    final user = authUsername?.trim() ?? '';
    final pass = authPassword?.trim() ?? '';
    return user.isNotEmpty && pass.isNotEmpty;
  }

  String get hubAgentsUrl => ensureAgentsNamespaceUrl(serverUrl);

  LocalAgentHubConfig copyWith({
    String? authToken,
    String? refreshToken,
    String? authUsername,
    String? authPassword,
  }) {
    return LocalAgentHubConfig(
      configId: configId,
      serverUrl: serverUrl,
      agentId: agentId,
      authToken: authToken ?? this.authToken,
      refreshToken: refreshToken ?? this.refreshToken,
      authUsername: authUsername ?? this.authUsername,
      authPassword: authPassword ?? this.authPassword,
    );
  }
}

class LocalAgentHubSecureSecrets {
  const LocalAgentHubSecureSecrets({
    this.authToken,
    this.refreshToken,
    this.authPassword,
  });

  final String? authToken;
  final String? refreshToken;
  final String? authPassword;
}

LocalAgentHubSecureSecrets readHubSecretsFromStorageMap(
  String configId,
  Map<String, String> storage,
) {
  final trimmedConfigId = configId.trim();
  if (trimmedConfigId.isEmpty) {
    return const LocalAgentHubSecureSecrets();
  }

  String? readSecret(String suffix) {
    final value = storage['hub_auth_secret_${trimmedConfigId}_$suffix']?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  return LocalAgentHubSecureSecrets(
    authToken: readSecret('auth_token'),
    refreshToken: readSecret('refresh_token'),
    authPassword: readSecret('auth_password'),
  );
}

LocalAgentHubSecureSecrets readHubSecretsFromSecureStorage(String configId) {
  if (!Platform.isWindows) {
    return const LocalAgentHubSecureSecrets();
  }

  return readHubSecretsFromStorageMap(
    configId,
    readPlugAgenteWindowsSecureStorage(),
  );
}

LocalAgentHubConfig mergeLocalHubConfigWithSecureStorageMap(
  LocalAgentHubConfig config,
  Map<String, String> storage,
) {
  final secrets = readHubSecretsFromStorageMap(config.configId, storage);
  return config.copyWith(
    authToken: (config.authToken?.trim().isNotEmpty ?? false) ? config.authToken : secrets.authToken,
    refreshToken: (config.refreshToken?.trim().isNotEmpty ?? false) ? config.refreshToken : secrets.refreshToken,
    authPassword: (config.authPassword?.trim().isNotEmpty ?? false) ? config.authPassword : secrets.authPassword,
  );
}

LocalAgentHubConfig mergeLocalHubConfigWithSecureStorage(LocalAgentHubConfig config) {
  if (!Platform.isWindows) {
    return config;
  }

  return mergeLocalHubConfigWithSecureStorageMap(
    config,
    readPlugAgenteWindowsSecureStorage(),
  );
}

LocalAgentHubConfig? readLatestResolvedLocalAgentHubConfig() {
  final config = readLatestLocalAgentHubConfig();
  if (config == null) {
    return null;
  }
  return mergeLocalHubConfigWithSecureStorage(config);
}

LocalAgentHubConfig? readLatestLocalAgentHubConfig() {
  final dbPath = findAgentConfigDatabasePath();
  if (dbPath == null) {
    return null;
  }

  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    final result = db.select('''
SELECT id, server_url, agent_id, auth_token, refresh_token, auth_username, auth_password
FROM config_table
ORDER BY updated_at DESC
LIMIT 1
''');
    if (result.isEmpty) {
      return null;
    }
    final row = result.first;
    return LocalAgentHubConfig(
      configId: (row['id'] as String?)?.trim() ?? '',
      serverUrl: (row['server_url'] as String?)?.trim() ?? '',
      agentId: (row['agent_id'] as String?)?.trim() ?? '',
      authToken: row['auth_token'] as String?,
      refreshToken: row['refresh_token'] as String?,
      authUsername: row['auth_username'] as String?,
      authPassword: row['auth_password'] as String?,
    );
  } finally {
    db.dispose();
  }
}
