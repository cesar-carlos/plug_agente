import 'package:drift/drift.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/value_objects/hub_auth_secrets.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:result_dart/result_dart.dart';

class AgentConfigRepository implements IAgentConfigRepository {
  AgentConfigRepository(
    this._database, {
    required IHubAuthSecretStore authSecretStore,
  }) : _authSecretStore = authSecretStore;

  final AppDatabase _database;
  final IHubAuthSecretStore _authSecretStore;

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
  Future<Result<List<Config>>> getAll() async {
    try {
      final configsData = await _database.select(_database.configTable).get();

      final configs = await Future.wait(
        configsData.map(_mapDataToEntity),
      );
      return Success(configs);
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
  Future<Result<Config>> save(Config config) async {
    try {
      final configData = await _mapEntityToData(config);

      await _database.into(_database.configTable).insertOnConflictUpdate(configData);

      return Success(config);
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
      await (_database.delete(
        _database.configTable,
      )..where((tbl) => tbl.id.equals(id))).go();
      await _authSecretStore.deleteSecrets(id);

      // For Result<void>, we use a unit value
      return const Success<Object, Exception>(Object());
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
      connectionString: config.connectionString,
      username: config.username,
      password: config.password,
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
    final secrets = await _loadSecrets(data);
    return Config(
      id: data.id,
      serverUrl: data.serverUrl,
      agentId: data.agentId,
      authToken: secrets.authToken,
      refreshToken: secrets.refreshToken,
      authUsername: data.authUsername,
      authPassword: secrets.authPassword,
      driverName: data.driverName,
      odbcDriverName: data.odbcDriverName,
      connectionString: data.connectionString,
      username: data.username,
      password: data.password,
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

  Future<HubAuthSecrets> _persistSecretsForSave(
    String configId,
    HubAuthSecrets secrets,
  ) async {
    if (!_authSecretStore.isAvailable) {
      return secrets;
    }

    try {
      if (secrets.hasAny) {
        await _authSecretStore.saveSecrets(configId, secrets);
      } else {
        await _authSecretStore.deleteSecrets(configId);
      }
      return const HubAuthSecrets();
    } on Exception {
      return secrets;
    }
  }

  Future<HubAuthSecrets> _loadSecrets(ConfigData data) async {
    final legacySecrets = HubAuthSecrets(
      authToken: data.authToken,
      refreshToken: data.refreshToken,
      authPassword: data.authPassword,
    );
    if (!_authSecretStore.isAvailable) {
      return legacySecrets;
    }

    try {
      final storedSecrets = await _authSecretStore.readSecrets(data.id);
      final mergedSecrets = storedSecrets.mergeMissingFrom(legacySecrets);
      if (_needsSecureMigration(storedSecrets, legacySecrets)) {
        await _authSecretStore.saveSecrets(data.id, mergedSecrets);
        await _clearLegacySecretColumns(data.id);
      }
      return mergedSecrets;
    } on Exception {
      return legacySecrets;
    }
  }

  Future<void> _clearLegacySecretColumns(String configId) async {
    await (_database.update(_database.configTable)..where((tbl) => tbl.id.equals(configId))).write(
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

    final needsAuthToken =
        (legacySecrets.authToken?.trim().isNotEmpty ?? false) && !(storedSecrets.authToken?.trim().isNotEmpty ?? false);
    final needsRefreshToken =
        (legacySecrets.refreshToken?.trim().isNotEmpty ?? false) &&
        !(storedSecrets.refreshToken?.trim().isNotEmpty ?? false);
    final needsPassword =
        (legacySecrets.authPassword?.trim().isNotEmpty ?? false) &&
        !(storedSecrets.authPassword?.trim().isNotEmpty ?? false);
    return needsAuthToken || needsRefreshToken || needsPassword;
  }
}
