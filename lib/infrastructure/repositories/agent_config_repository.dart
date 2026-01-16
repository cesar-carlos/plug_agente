import 'package:result_dart/result_dart.dart';
import 'package:drift/drift.dart';
import '../../domain/entities/config.dart';
import '../../domain/repositories/i_agent_config_repository.dart';
import '../../domain/errors/failures.dart' as domain;
import 'agent_config_drift_database.dart';

class AgentConfigRepository implements IAgentConfigRepository {
  final AppDatabase _database;

  AgentConfigRepository(this._database);

  @override
  Future<Result<Config>> getById(String id) async {
    try {
      final configData = await (_database.select(
        _database.configTable,
      )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

      if (configData == null) {
        return Failure(domain.NotFoundFailure('Config not found'));
      }

      final config = _mapDataToEntity(configData);
      return Success(config);
    } catch (e) {
      return Failure(domain.DatabaseFailure('Failed to get config: $e'));
    }
  }

  @override
  Future<Result<List<Config>>> getAll() async {
    try {
      final configsData = await (_database.select(_database.configTable)).get();

      final configs = configsData.map(_mapDataToEntity).toList();
      return Success(configs);
    } catch (e) {
      return Failure(domain.DatabaseFailure('Failed to get all configs: $e'));
    }
  }

  @override
  Future<Result<Config>> save(Config config) async {
    try {
      final configData = _mapEntityToData(config);

      await _database.into(_database.configTable).insertOnConflictUpdate(configData);

      return Success(config);
    } catch (e) {
      return Failure(domain.DatabaseFailure('Failed to save config: $e'));
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    try {
      await (_database.delete(_database.configTable)..where((tbl) => tbl.id.equals(id))).go();

      // For Result<void>, we use a unit value
      return Success<Object, Exception>(Object());
    } catch (e) {
      return Failure(domain.DatabaseFailure('Failed to delete config: $e'));
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

      final config = _mapDataToEntity(configData);
      return Success(config);
    } catch (e) {
      return Failure(domain.DatabaseFailure('Failed to get current config: $e'));
    }
  }

  ConfigData _mapEntityToData(Config config) {
    return ConfigData(
      id: config.id,
      serverUrl: config.serverUrl,
      agentId: config.agentId,
      authToken: config.authToken,
      refreshToken: config.refreshToken,
      authUsername: config.authUsername,
      authPassword: config.authPassword,
      driverName: config.driverName,
      connectionString: config.connectionString,
      username: config.username,
      password: config.password,
      databaseName: config.databaseName,
      host: config.host,
      port: config.port,
      createdAt: config.createdAt,
      updatedAt: config.updatedAt,
    );
  }

  Config _mapDataToEntity(ConfigData data) {
    return Config(
      id: data.id,
      serverUrl: data.serverUrl,
      agentId: data.agentId,
      authToken: data.authToken,
      refreshToken: data.refreshToken,
      authUsername: data.authUsername,
      authPassword: data.authPassword,
      driverName: data.driverName,
      connectionString: data.connectionString,
      username: data.username,
      password: data.password,
      databaseName: data.databaseName,
      host: data.host,
      port: data.port,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }
}
