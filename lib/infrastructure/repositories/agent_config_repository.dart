import 'package:drift/drift.dart';
import 'package:plug_agente/core/utils/odbc_connection_string_secrets.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_hub_session_store.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_store.dart';
import 'package:plug_agente/domain/value_objects/config_row_legacy_secrets.dart';
import 'package:plug_agente/domain/value_objects/hub_auth_secrets.dart';
import 'package:plug_agente/domain/value_objects/hub_stored_credentials_state.dart';
import 'package:plug_agente/domain/value_objects/hub_stored_session.dart';
import 'package:plug_agente/domain/value_objects/odbc_credential_secrets.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/stores/secure_storage_guard.dart';
import 'package:result_dart/result_dart.dart';

class AgentConfigRepository implements IAgentConfigRepository {
  AgentConfigRepository(
    this._database, {
    required IHubAuthSecretStore authSecretStore,
    required IHubSessionStore hubSessionStore,
    required IOdbcCredentialSecretStore odbcCredentialSecretStore,
    required IOdbcCredentialStore odbcCredentialStore,
  }) : _authSecretStore = authSecretStore,
       _hubSessionStore = hubSessionStore,
       _odbcCredentialSecretStore = odbcCredentialSecretStore,
       _odbcCredentialStore = odbcCredentialStore;

  final AppDatabase _database;
  final IHubAuthSecretStore _authSecretStore;
  final IHubSessionStore _hubSessionStore;
  final IOdbcCredentialSecretStore _odbcCredentialSecretStore;
  final IOdbcCredentialStore _odbcCredentialStore;

  domain.DatabaseFailure _buildDatabaseFailure(
    String message, {
    Object? cause,
    Map<String, dynamic> context = const {},
  }) {
    return domain.DatabaseFailure.withContext(
      message: message,
      cause: cause,
      context: context,
    );
  }

  @override
  Future<Result<Config>> getById(String id) async {
    try {
      final configData = await (_database.select(
        _database.configTable,
      )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

      if (configData == null) {
        return Failure(domain.NotFoundFailure('Config not found'));
      }

      final config = await _mapDataToEntity(configData);
      return Success(config);
    } on domain.Failure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to load configuration',
          cause: error,
          context: {
            'operation': 'getById',
            'configId': id,
          },
        ),
      );
    }
  }

  @override
  Future<Result<Config>> getByIdMetadata(String id) async {
    try {
      final configData = await (_database.select(
        _database.configTable,
      )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

      if (configData == null) {
        return Failure(domain.NotFoundFailure('Config not found'));
      }

      return Success(_mapDataToEntityMetadata(configData));
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to load configuration metadata',
          cause: error,
          context: {
            'operation': 'getByIdMetadata',
            'configId': id,
          },
        ),
      );
    }
  }

  @override
  Future<Result<List<Config>>> getAll() async {
    try {
      final configsData = await _database.select(_database.configTable).get();
      if (configsData.isEmpty) {
        return const Success(<Config>[]);
      }

      final configs = await _mapDataListToEntities(configsData);
      return Success(configs);
    } on domain.Failure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to load configurations',
          cause: error,
          context: {'operation': 'getAll'},
        ),
      );
    }
  }

  @override
  Future<Result<List<Config>>> getAllMetadata() async {
    try {
      final configsData = await _database.select(_database.configTable).get();
      return Success(configsData.map(_mapDataToEntityMetadata).toList(growable: false));
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to load configuration metadata list',
          cause: error,
          context: {'operation': 'getAllMetadata'},
        ),
      );
    }
  }

  @override
  Future<Result<Config>> save(Config config) async {
    try {
      final configData = await _mapEntityToData(config);

      await _database.into(_database.configTable).insertOnConflictUpdate(configData);

      return Success(config);
    } on domain.Failure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to save configuration',
          cause: error,
          context: {
            'operation': 'save',
            'configId': config.id,
          },
        ),
      );
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    try {
      final clearHubSecretsResult = await _hubSessionStore.deleteAllSecrets(id);
      if (clearHubSecretsResult.isError()) {
        return Failure(clearHubSecretsResult.exceptionOrNull()!);
      }

      final clearOdbcSecretsResult = await _odbcCredentialStore.deleteAllSecrets(id);
      if (clearOdbcSecretsResult.isError()) {
        return Failure(clearOdbcSecretsResult.exceptionOrNull()!);
      }

      await (_database.delete(
        _database.configTable,
      )..where((tbl) => tbl.id.equals(id))).go();
      return const Success(unit);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to delete configuration',
          cause: error,
          context: {
            'operation': 'delete',
            'configId': id,
          },
        ),
      );
    }
  }

  @override
  Future<Result<Config>> getCurrentConfig() async {
    try {
      final configData =
          await (_database.select(_database.configTable)
                ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)])
                ..limit(1))
              .getSingleOrNull();

      if (configData == null) {
        return Failure(domain.NotFoundFailure('No config found'));
      }

      final config = await _mapDataToEntity(configData);
      return Success(config);
    } on domain.Failure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to load current configuration',
          cause: error,
          context: {'operation': 'getCurrentConfig'},
        ),
      );
    }
  }

  @override
  Future<Result<Config>> getCurrentConfigMetadata() async {
    try {
      final configData =
          await (_database.select(_database.configTable)
                ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)])
                ..limit(1))
              .getSingleOrNull();

      if (configData == null) {
        return Failure(domain.NotFoundFailure('No config found'));
      }

      return Success(_mapDataToEntityMetadata(configData));
    } on Exception catch (error) {
      return Failure(
        _buildDatabaseFailure(
          'Failed to load current configuration metadata',
          cause: error,
          context: {'operation': 'getCurrentConfigMetadata'},
        ),
      );
    }
  }

  Future<ConfigData> _mapEntityToData(Config config) async {
    final secrets = HubAuthSecrets(
      authToken: config.authToken,
      refreshToken: config.refreshToken,
      authPassword: config.authPassword,
    );
    final persistedSecrets = await _persistSecretsForSave(
      config.id,
      secrets,
    );
    final persistedOdbcSecrets = await _persistOdbcSecretsForSave(config);
    return ConfigData(
      id: config.id,
      serverUrl: config.serverUrl,
      agentId: config.agentId,
      authToken: persistedSecrets.authToken,
      refreshToken: persistedSecrets.refreshToken,
      authUsername: config.authUsername,
      authPassword: persistedSecrets.authPassword,
      driverName: config.driverName,
      odbcDriverName: config.odbcDriverName,
      connectionString: persistedOdbcSecrets.connectionString,
      username: config.username,
      databaseName: config.databaseName,
      host: config.host,
      port: config.port,
      nome: config.nome,
      nomeFantasia: config.nomeFantasia,
      cnaeCnpjCpf: config.cnaeCnpjCpf,
      telefone: config.telefone,
      celular: config.celular,
      email: config.email,
      endereco: config.endereco,
      numeroEndereco: config.numeroEndereco,
      bairro: config.bairro,
      cep: config.cep,
      nomeMunicipio: config.nomeMunicipio,
      ufMunicipio: config.ufMunicipio,
      observacao: config.observacao,
      hubProfileVersion: config.hubProfileVersion,
      hubProfileUpdatedAt: config.hubProfileUpdatedAt,
      createdAt: config.createdAt,
      updatedAt: config.updatedAt,
    );
  }

  Future<Config> _mapDataToEntity(ConfigData data) async {
    final configs = await _mapDataListToEntities([data]);
    return configs.single;
  }

  Future<List<Config>> _mapDataListToEntities(List<ConfigData> configsData) async {
    final legacyRows = configsData.map(_legacySecretsFromConfigData).toList(growable: false);

    final hubBundleResult = await _hubSessionStore.readLegacyRowBundle(legacyRows);
    if (hubBundleResult.isError()) {
      throw hubBundleResult.exceptionOrNull()!;
    }
    final hubBundle = hubBundleResult.getOrThrow();

    final odbcCredentialsResult = await _odbcCredentialStore.readCredentialsForLegacyRows(
      legacyRows,
    );
    if (odbcCredentialsResult.isError()) {
      throw odbcCredentialsResult.exceptionOrNull()!;
    }
    final odbcCredentialsById = odbcCredentialsResult.getOrThrow();

    return configsData
        .map((data) {
          final metadataConfig = _mapDataToEntityMetadata(data);
          final session = hubBundle.sessions[data.id] ?? const HubStoredSession();
          final credentials = hubBundle.credentials[data.id] ?? const HubStoredCredentialsState();
          final odbcCredentials = odbcCredentialsById[data.id] ?? const OdbcCredentialSecrets();
          return metadataConfig.copyWith(
            authToken: session.token?.token,
            refreshToken: session.token?.refreshToken,
            authPassword: credentials.credentials?.password,
            password: odbcCredentials.password,
          );
        })
        .toList(growable: false);
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

  Config _mapDataToEntityMetadata(ConfigData data) {
    // Hub auth credentials must never come from the Drift row directly in the
    // metadata path — they are always read from IHubSessionStore in the full
    // getById() flow. Nulling them here prevents legacy plaintext values
    // (rows written before the secure-store migration) from leaking into
    // agent.getProfile / health / ODBC metadata consumers.
    return Config(
      id: data.id,
      serverUrl: data.serverUrl,
      agentId: data.agentId,
      // authToken, refreshToken, authPassword intentionally omitted (default null)
      // to prevent legacy Drift plaintext values from leaking out.
      authUsername: data.authUsername,
      driverName: data.driverName,
      odbcDriverName: data.odbcDriverName,
      connectionString: OdbcConnectionStringSecrets.stripPasswordFromConnectionString(
        data.connectionString,
      ),
      username: data.username,
      databaseName: data.databaseName,
      host: data.host,
      port: data.port,
      nome: data.nome,
      nomeFantasia: data.nomeFantasia,
      cnaeCnpjCpf: data.cnaeCnpjCpf,
      telefone: data.telefone,
      celular: data.celular,
      email: data.email,
      endereco: data.endereco,
      numeroEndereco: data.numeroEndereco,
      bairro: data.bairro,
      cep: data.cep,
      nomeMunicipio: data.nomeMunicipio,
      ufMunicipio: data.ufMunicipio,
      observacao: data.observacao,
      hubProfileVersion: data.hubProfileVersion,
      hubProfileUpdatedAt: data.hubProfileUpdatedAt,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  Future<({String connectionString})> _persistOdbcSecretsForSave(
    Config config,
  ) async {
    if (!_odbcCredentialSecretStore.isAvailable) {
      final incomingPassword =
          _normalize(config.password) ??
          OdbcConnectionStringSecrets.extractPasswordFromConnectionString(
            config.connectionString,
          );
      if (incomingPassword != null) {
        throw SecureStorageGuard.unavailableFailure(
          operation: 'persistOdbcCredentials',
          store: 'odbc',
        );
      }
      return (connectionString: config.connectionString);
    }

    try {
      final incomingPassword =
          _normalize(config.password) ??
          OdbcConnectionStringSecrets.extractPasswordFromConnectionString(
            config.connectionString,
          );
      final currentSecrets = await _odbcCredentialSecretStore.readSecrets(config.id);
      final passwordToPersist = incomingPassword ?? _normalize(currentSecrets.password);
      final secretsToPersist = OdbcCredentialSecrets(password: passwordToPersist);

      if (secretsToPersist.hasAny) {
        await _odbcCredentialSecretStore.saveSecrets(config.id, secretsToPersist);
      } else {
        await _odbcCredentialSecretStore.deleteSecrets(config.id);
      }

      return (
        connectionString: OdbcConnectionStringSecrets.stripPasswordFromConnectionString(
          config.connectionString,
        ),
      );
    } on Exception catch (error) {
      throw domain.DatabaseFailure.withContext(
        message: 'Failed to persist ODBC credentials securely',
        cause: error,
        context: {
          'operation': 'persistOdbcCredentials',
          'configId': config.id,
        },
      );
    }
  }

  Future<HubAuthSecrets> _persistSecretsForSave(
    String configId,
    HubAuthSecrets secrets,
  ) async {
    if (!_authSecretStore.isAvailable) {
      if (secrets.hasAny) {
        throw SecureStorageGuard.unavailableFailure(
          operation: 'persistHubAuthSecrets',
          store: 'hub_auth',
        );
      }
      return const HubAuthSecrets();
    }

    try {
      final currentSecrets = await _authSecretStore.readSecrets(configId);
      final secretsToPersist = HubAuthSecrets(
        authToken: _normalize(currentSecrets.authToken) ?? _normalize(secrets.authToken),
        refreshToken: _normalize(currentSecrets.refreshToken) ?? _normalize(secrets.refreshToken),
        authPassword: _normalize(secrets.authPassword),
      );

      if (secretsToPersist.hasAny) {
        await _authSecretStore.saveSecrets(configId, secretsToPersist);
      } else {
        await _authSecretStore.deleteSecrets(configId);
      }
      return const HubAuthSecrets();
    } on Exception catch (error) {
      throw domain.DatabaseFailure.withContext(
        message: 'Failed to persist hub authentication secrets securely',
        cause: error,
        context: {
          'operation': 'persistHubAuthSecrets',
          'configId': configId,
        },
      );
    }
  }

  String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
