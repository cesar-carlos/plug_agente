import 'package:drift/drift.dart';
import 'package:plug_agente/core/utils/odbc_connection_string_secrets.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_odbc_credential_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_store.dart';
import 'package:plug_agente/domain/value_objects/config_row_legacy_secrets.dart';
import 'package:plug_agente/domain/value_objects/odbc_credential_secrets.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:result_dart/result_dart.dart';

class OdbcCredentialStore implements IOdbcCredentialStore {
  OdbcCredentialStore(
    this._database, {
    required IOdbcCredentialSecretStore credentialSecretStore,
  }) : _credentialSecretStore = credentialSecretStore;

  final AppDatabase _database;
  final IOdbcCredentialSecretStore _credentialSecretStore;

  @override
  Future<Result<OdbcCredentialSecrets>> readCredentials(String configId) async {
    try {
      final configData = await _loadConfigData(configId);
      if (configData == null) {
        return Failure(domain.NotFoundFailure('Config not found'));
      }

      final secretsResult = await _loadMergedSecrets(configData);
      if (secretsResult.isError()) {
        return Failure(secretsResult.exceptionOrNull()!);
      }

      return Success(secretsResult.getOrThrow());
    } on domain.Failure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to read stored ODBC credentials',
          cause: error,
          context: {
            'operation': 'readCredentials',
            'configId': configId,
          },
        ),
      );
    }
  }

  @override
  Future<Result<Map<String, OdbcCredentialSecrets>>> readCredentialsForLegacyRows(
    List<ConfigRowLegacySecrets> rows,
  ) async {
    try {
      if (rows.isEmpty) {
        return const Success(<String, OdbcCredentialSecrets>{});
      }

      final secretsResult = await _loadMergedOdbcSecretsForLegacyRows(rows);
      if (secretsResult.isError()) {
        return Failure(secretsResult.exceptionOrNull()!);
      }

      return Success(secretsResult.getOrThrow());
    } on domain.Failure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to read stored ODBC credentials',
          cause: error,
          context: {
            'operation': 'readCredentialsForLegacyRows',
            'configCount': rows.length,
          },
        ),
      );
    }
  }

  @override
  Future<Result<void>> deleteAllSecrets(String configId) async {
    try {
      if (_credentialSecretStore.isAvailable) {
        await _credentialSecretStore.deleteSecrets(configId);
      }
      await _clearLegacyOdbcColumns(configId);
      return const Success(unit);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to delete ODBC credentials',
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

  Future<Result<OdbcCredentialSecrets>> _loadMergedSecrets(ConfigData data) async {
    final secretsResult = await _loadMergedOdbcSecretsForLegacyRows(
      [_legacySecretsFromConfigData(data)],
    );
    if (secretsResult.isError()) {
      return Failure(secretsResult.exceptionOrNull()!);
    }

    return Success(
      secretsResult.getOrThrow()[data.id] ?? const OdbcCredentialSecrets(),
    );
  }

  Future<Result<Map<String, OdbcCredentialSecrets>>> _loadMergedOdbcSecretsForLegacyRows(
    List<ConfigRowLegacySecrets> rows,
  ) async {
    if (rows.isEmpty) {
      return const Success(<String, OdbcCredentialSecrets>{});
    }

    if (!_credentialSecretStore.isAvailable) {
      return Success({
        for (final row in rows) row.configId: row.odbcLegacySecrets,
      });
    }

    try {
      final storedSecretsById = await _credentialSecretStore.readSecretsForConfigIds(
        rows.map((row) => row.configId),
      );
      final mergedSecretsById = <String, OdbcCredentialSecrets>{};

      for (final row in rows) {
        final legacySecrets = row.odbcLegacySecrets;
        final storedSecrets = storedSecretsById[row.configId] ?? const OdbcCredentialSecrets();
        final mergedSecrets = storedSecrets.mergeMissingFrom(legacySecrets);
        if (_needsSecureMigration(storedSecrets, legacySecrets)) {
          await _credentialSecretStore.saveSecrets(row.configId, mergedSecrets);
          await _clearLegacyOdbcColumns(row.configId);
        }
        mergedSecretsById[row.configId] = mergedSecrets;
      }

      return Success(mergedSecretsById);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to read secure ODBC credentials',
          cause: error,
          context: {
            'operation': 'readSecureOdbcCredentials',
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

  Future<void> _clearLegacyOdbcColumns(String configId) async {
    final configData = await _loadConfigData(configId);
    if (configData == null) {
      return;
    }

    final redactedConnectionString = OdbcConnectionStringSecrets.stripPasswordFromConnectionString(
      configData.connectionString,
    );
    await (_database.update(
      _database.configTable,
    )..where((tbl) => tbl.id.equals(configId))).write(
      ConfigTableCompanion(
        connectionString: Value<String>(redactedConnectionString),
      ),
    );
  }

  bool _needsSecureMigration(
    OdbcCredentialSecrets storedSecrets,
    OdbcCredentialSecrets legacySecrets,
  ) {
    if (!legacySecrets.hasAny) {
      return false;
    }

    final needsPassword = _normalize(legacySecrets.password) != null && _normalize(storedSecrets.password) == null;
    return needsPassword;
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
