import 'package:drift/drift.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_hub_session_store.dart';
import 'package:plug_agente/domain/value_objects/config_row_legacy_secrets.dart';
import 'package:plug_agente/domain/value_objects/hub_auth_secrets.dart';
import 'package:plug_agente/domain/value_objects/hub_session_legacy_row_bundle.dart';
import 'package:plug_agente/domain/value_objects/hub_stored_credentials.dart';
import 'package:plug_agente/domain/value_objects/hub_stored_credentials_state.dart';
import 'package:plug_agente/domain/value_objects/hub_stored_session.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/stores/secure_storage_guard.dart';
import 'package:result_dart/result_dart.dart';

class HubSessionStore implements IHubSessionStore {
  HubSessionStore(
    this._database, {
    required IHubAuthSecretStore authSecretStore,
  }) : _authSecretStore = authSecretStore;

  final AppDatabase _database;
  final IHubAuthSecretStore _authSecretStore;

  @override
  Future<Result<HubStoredSession>> readSession(String configId) async {
    try {
      final configData = await _loadConfigData(configId);
      if (configData == null) {
        return Failure(domain.NotFoundFailure('Config not found'));
      }

      final secretsResult = await _loadMergedSecrets(configData);
      if (secretsResult.isError()) {
        return Failure(secretsResult.exceptionOrNull()!);
      }

      final secrets = secretsResult.getOrThrow();
      final authToken = _normalize(secrets.authToken);
      final refreshToken = _normalize(secrets.refreshToken);
      if (authToken == null || refreshToken == null) {
        return const Success(HubStoredSession());
      }

      return Success(
        HubStoredSession(
          token: AuthToken(
            token: authToken,
            refreshToken: refreshToken,
          ),
        ),
      );
    } on domain.Failure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to read stored hub session',
          cause: error,
          context: {
            'operation': 'readSession',
            'configId': configId,
          },
        ),
      );
    }
  }

  @override
  Future<Result<void>> writeSessionTokens(
    String configId,
    AuthToken token,
  ) async {
    try {
      final configData = await _loadConfigData(configId);
      if (configData == null) {
        return Failure(domain.NotFoundFailure('Config not found'));
      }

      if (!_authSecretStore.isAvailable) {
        return Failure(
          SecureStorageGuard.unavailableFailure(
            operation: 'writeSessionTokens',
            store: 'hub_auth',
          ),
        );
      }

      final secretsResult = await _loadMergedSecrets(configData);
      if (secretsResult.isError()) {
        return Failure(secretsResult.exceptionOrNull()!);
      }

      final currentSecrets = secretsResult.getOrThrow();
      await _authSecretStore.saveSecrets(
        configId,
        HubAuthSecrets(
          authToken: token.token,
          refreshToken: token.refreshToken,
          authPassword: currentSecrets.authPassword,
        ),
      );
      await _clearLegacyTokenColumns(configId);
      return const Success(unit);
    } on domain.Failure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to persist hub session tokens',
          cause: error,
          context: {
            'operation': 'writeSessionTokens',
            'configId': configId,
          },
        ),
      );
    }
  }

  @override
  Future<Result<void>> clearSession(String configId) async {
    try {
      final configData = await _loadConfigData(configId);
      if (configData == null) {
        return Failure(domain.NotFoundFailure('Config not found'));
      }

      if (!_authSecretStore.isAvailable) {
        await _updateLegacySecrets(
          configId,
          authToken: null,
          refreshToken: null,
        );
        return const Success(unit);
      }

      final secretsResult = await _loadMergedSecrets(configData);
      if (secretsResult.isError()) {
        return Failure(secretsResult.exceptionOrNull()!);
      }

      final currentSecrets = secretsResult.getOrThrow();
      if (_normalize(currentSecrets.authPassword) == null) {
        await _authSecretStore.deleteSecrets(configId);
      } else {
        await _authSecretStore.saveSecrets(
          configId,
          HubAuthSecrets(authPassword: currentSecrets.authPassword),
        );
      }
      await _clearLegacyTokenColumns(configId);
      return const Success(unit);
    } on domain.Failure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to clear stored hub session',
          cause: error,
          context: {
            'operation': 'clearSession',
            'configId': configId,
          },
        ),
      );
    }
  }

  @override
  Future<Result<HubSessionLegacyRowBundle>> readLegacyRowBundle(
    List<ConfigRowLegacySecrets> rows,
  ) async {
    try {
      if (rows.isEmpty) {
        return const Success(
          HubSessionLegacyRowBundle(
            sessions: <String, HubStoredSession>{},
            credentials: <String, HubStoredCredentialsState>{},
          ),
        );
      }

      final secretsResult = await _loadMergedHubSecretsForLegacyRows(rows);
      if (secretsResult.isError()) {
        return Failure(secretsResult.exceptionOrNull()!);
      }

      final secretsById = secretsResult.getOrThrow();
      final sessions = <String, HubStoredSession>{};
      final credentialsById = <String, HubStoredCredentialsState>{};
      for (final row in rows) {
        final secrets = secretsById[row.configId] ?? const HubAuthSecrets();
        final authToken = _normalize(secrets.authToken);
        final refreshToken = _normalize(secrets.refreshToken);
        if (authToken == null || refreshToken == null) {
          sessions[row.configId] = const HubStoredSession();
        } else {
          sessions[row.configId] = HubStoredSession(
            token: AuthToken(
              token: authToken,
              refreshToken: refreshToken,
            ),
          );
        }

        final username = row.normalizedAuthUsername;
        if (username == null) {
          credentialsById[row.configId] = const HubStoredCredentialsState();
          continue;
        }

        final password = _normalize(secrets.authPassword);
        if (password == null) {
          credentialsById[row.configId] = const HubStoredCredentialsState();
          continue;
        }

        credentialsById[row.configId] = HubStoredCredentialsState(
          credentials: HubStoredCredentials(
            username: username,
            password: password,
          ),
        );
      }

      return Success(
        HubSessionLegacyRowBundle(
          sessions: sessions,
          credentials: credentialsById,
        ),
      );
    } on domain.Failure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to read stored hub session bundle',
          cause: error,
          context: {
            'operation': 'readLegacyRowBundle',
            'configCount': rows.length,
          },
        ),
      );
    }
  }

  @override
  Future<Result<HubStoredCredentialsState>> readStoredCredentials(
    String configId,
  ) async {
    try {
      final configData = await _loadConfigData(configId);
      if (configData == null) {
        return Failure(domain.NotFoundFailure('Config not found'));
      }

      final username = _normalize(configData.authUsername);
      if (username == null) {
        return const Success(HubStoredCredentialsState());
      }

      final secretsResult = await _loadMergedSecrets(configData);
      if (secretsResult.isError()) {
        return Failure(secretsResult.exceptionOrNull()!);
      }

      final password = _normalize(secretsResult.getOrThrow().authPassword);
      if (password == null) {
        return const Success(HubStoredCredentialsState());
      }

      return Success(
        HubStoredCredentialsState(
          credentials: HubStoredCredentials(
            username: username,
            password: password,
          ),
        ),
      );
    } on domain.Failure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to read stored hub credentials',
          cause: error,
          context: {
            'operation': 'readStoredCredentials',
            'configId': configId,
          },
        ),
      );
    }
  }

  @override
  Future<Result<void>> deleteAllSecrets(String configId) async {
    try {
      if (_authSecretStore.isAvailable) {
        await _authSecretStore.deleteSecrets(configId);
      }
      await _clearLegacySecretColumns(configId);
      return const Success(unit);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to delete hub authentication secrets',
          cause: error,
          context: {
            'operation': 'deleteAllSecrets',
            'configId': configId,
          },
        ),
      );
    }
  }

  Future<ConfigData?> _loadConfigData(String configId) {
    return (_database.select(
      _database.configTable,
    )..where((tbl) => tbl.id.equals(configId))).getSingleOrNull();
  }

  Future<Result<HubAuthSecrets>> _loadMergedSecrets(ConfigData data) async {
    final secretsResult = await _loadMergedHubSecretsForLegacyRows(
      [_legacySecretsFromConfigData(data)],
    );
    if (secretsResult.isError()) {
      return Failure(secretsResult.exceptionOrNull()!);
    }

    return Success(
      secretsResult.getOrThrow()[data.id] ?? const HubAuthSecrets(),
    );
  }

  Future<Result<Map<String, HubAuthSecrets>>> _loadMergedHubSecretsForLegacyRows(
    List<ConfigRowLegacySecrets> rows,
  ) async {
    if (rows.isEmpty) {
      return const Success(<String, HubAuthSecrets>{});
    }

    if (!_authSecretStore.isAvailable) {
      return Success({
        for (final row in rows) row.configId: row.hubAuthSecrets,
      });
    }

    try {
      final storedSecretsById = await _authSecretStore.readSecretsForConfigIds(
        rows.map((row) => row.configId),
      );
      final mergedSecretsById = <String, HubAuthSecrets>{};

      for (final row in rows) {
        final legacySecrets = row.hubAuthSecrets;
        final storedSecrets = storedSecretsById[row.configId] ?? const HubAuthSecrets();
        final mergedSecrets = storedSecrets.mergeMissingFrom(legacySecrets);
        if (_needsSecureMigration(storedSecrets, legacySecrets)) {
          await _authSecretStore.saveSecrets(row.configId, mergedSecrets);
          await _clearLegacySecretColumns(row.configId);
        }
        mergedSecretsById[row.configId] = mergedSecrets;
      }

      return Success(mergedSecretsById);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to read secure hub authentication secrets',
          cause: error,
          context: {
            'operation': 'readSecureHubAuthSecrets',
            'configCount': rows.length,
          },
        ),
      );
    }
  }

  ConfigRowLegacySecrets _legacySecretsFromConfigData(ConfigData data) {
    return ConfigRowLegacySecrets(
      configId: data.id,
      authToken: data.authToken,
      refreshToken: data.refreshToken,
      authPassword: data.authPassword,
      authUsername: data.authUsername,
      connectionString: data.connectionString,
    );
  }

  Future<void> _updateLegacySecrets(
    String configId, {
    required String? authToken,
    required String? refreshToken,
  }) {
    return (_database.update(
      _database.configTable,
    )..where((tbl) => tbl.id.equals(configId))).write(
      ConfigTableCompanion(
        authToken: Value<String?>(_normalize(authToken)),
        refreshToken: Value<String?>(_normalize(refreshToken)),
      ),
    );
  }

  Future<void> _clearLegacyTokenColumns(String configId) {
    return (_database.update(
      _database.configTable,
    )..where((tbl) => tbl.id.equals(configId))).write(
      const ConfigTableCompanion(
        authToken: Value<String?>(null),
        refreshToken: Value<String?>(null),
      ),
    );
  }

  Future<void> _clearLegacySecretColumns(String configId) {
    return (_database.update(
      _database.configTable,
    )..where((tbl) => tbl.id.equals(configId))).write(
      const ConfigTableCompanion(
        authToken: Value<String?>(null),
        refreshToken: Value<String?>(null),
        authPassword: Value<String?>(null),
      ),
    );
  }

  bool _needsSecureMigration(
    HubAuthSecrets storedSecrets,
    HubAuthSecrets legacySecrets,
  ) {
    if (!legacySecrets.hasAny) {
      return false;
    }

    final needsAuthToken = _normalize(legacySecrets.authToken) != null && _normalize(storedSecrets.authToken) == null;
    final needsRefreshToken =
        _normalize(legacySecrets.refreshToken) != null && _normalize(storedSecrets.refreshToken) == null;
    final needsPassword =
        _normalize(legacySecrets.authPassword) != null && _normalize(storedSecrets.authPassword) == null;
    return needsAuthToken || needsRefreshToken || needsPassword;
  }

  domain.DatabaseFailure _buildDatabaseFailure(
    String message, {
    Object? cause,
    Map<String, dynamic> context = const <String, dynamic>{},
  }) {
    return domain.DatabaseFailure.withContext(
      message: message,
      cause: cause,
      context: context,
    );
  }

  String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
