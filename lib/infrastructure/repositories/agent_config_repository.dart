import 'package:drift/drift.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:result_dart/result_dart.dart';

class AgentConfigRepository implements IAgentConfigRepository {
  AgentConfigRepository(this._database);
  final AppDatabase _database;

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

      final config = _mapDataToEntity(configData);
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

      final configs = configsData.map(_mapDataToEntity).toList();
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
      final configData = _mapEntityToData(config);

      await _database
          .into(_database.configTable)
          .insertOnConflictUpdate(configData);

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

      final config = _mapDataToEntity(configData);
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
      odbcDriverName: config.odbcDriverName,
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
      odbcDriverName: data.odbcDriverName,
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
