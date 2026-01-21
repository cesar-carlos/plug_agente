import 'package:result_dart/result_dart.dart';
import 'package:connect_database/connect_database.dart' as db;
import 'package:uuid/uuid.dart';

import '../../domain/entities/query_request.dart';
import '../../domain/entities/query_response.dart';
import '../../domain/repositories/i_database_gateway.dart';
import '../../domain/repositories/i_agent_config_repository.dart';
import '../../domain/errors/failures.dart' as domain;
import '../../infrastructure/config/database_type.dart';
import '../../infrastructure/config/database_config.dart';

class OdbcDatabaseGateway implements IDatabaseGateway {
  final Uuid _uuid;
  final IAgentConfigRepository _configRepository;

  OdbcDatabaseGateway(this._configRepository) : _uuid = const Uuid();

  /// Mapeia o nome amigável do driver para o DatabaseType correspondente
  DatabaseType _mapDriverNameToDatabaseType(String driverName) {
    return switch (driverName) {
      'SQL Server' => DatabaseType.sqlServer,
      'PostgreSQL' => DatabaseType.postgresql,
      'SQL Anywhere' => DatabaseType.sybaseAnywhere,
      _ => DatabaseType.sqlServer,
    };
  }

  /// Converte o DatabaseConfig local para o DatabaseConfig do connect_database
  db.DatabaseConfig _toConnectDatabaseConfig(DatabaseConfig localConfig) {
    switch (localConfig.databaseType) {
      case DatabaseType.sqlServer:
        return db.DatabaseConfig.sqlServer(
          driverName: localConfig.driverName,
          username: localConfig.username,
          password: localConfig.password,
          database: localConfig.database,
          server: localConfig.server,
          port: localConfig.port,
        );
      case DatabaseType.sybaseAnywhere:
        return db.DatabaseConfig.sybaseAnywhere(
          driverName: localConfig.driverName,
          username: localConfig.username,
          password: localConfig.password,
          database: localConfig.database,
          server: localConfig.server,
          port: localConfig.port,
        );
      case DatabaseType.postgresql:
        return db.DatabaseConfig.postgresql(
          driverName: localConfig.driverName,
          username: localConfig.username,
          password: localConfig.password,
          database: localConfig.database,
          server: localConfig.server,
          port: localConfig.port,
        );
    }
  }

  Future<Result<db.SqlCommand>> _connect(db.DatabaseConfig config) async {
    try {
      final command = db.SqlCommand(config);
      final result = await command.connect();
      return result.fold(
        (_) => Success(command),
        (failure) => Failure(domain.ConnectionFailure('Failed to connect: $failure')),
      );
    } catch (e) {
      return Failure(domain.ConnectionFailure('Failed to connect: $e'));
    }
  }

  Future<Result<void>> _disconnect(db.SqlCommand command) async {
    try {
      await command.close();
      return Success.unit();
    } catch (e) {
      return Failure(domain.ConnectionFailure('Failed to disconnect: $e'));
    }
  }

  Future<Result<List<Map<String, dynamic>>>> _executeQuery(
    db.SqlCommand command,
    String query,
    Map<String, dynamic>? params,
  ) async {
    try {
      command.commandText = query;

      // Definir parâmetros usando a sintaxe do connect_database
      if (params != null) {
        for (final entry in params.entries) {
          final value = entry.value;
          final param = command.param(entry.key);

          if (value == null) {
            // Para valores nulos, não definimos nada (o ODBC tratará como NULL)
            continue;
          } else if (value is int) {
            param.asInt = value;
          } else if (value is double) {
            param.asDouble = value;
          } else if (value is bool) {
            param.asBool = value;
          } else if (value is DateTime) {
            param.asDate = value;
          } else {
            param.asString = value.toString();
          }
        }
      }

      // Executar query usando open() para SELECT ou execute() para INSERT/UPDATE/DELETE
      final isSelect = query.trim().toUpperCase().startsWith('SELECT');
      final result = isSelect ? await command.open() : await command.execute();

      return result.fold((_) async {
        final data = <Map<String, dynamic>>[];
        if (isSelect) {
          // Usar stream() para obter registros como Map<String, dynamic>
          final streamResult = await command.stream();
          return await streamResult.fold((stream) async {
            await for (final record in stream) {
              data.add(record);
            }
            return Success(data);
          }, (failure) => Failure(domain.QueryExecutionFailure('Failed to stream results: $failure')));
        }
        return Success(data);
      }, (failure) => Failure(domain.QueryExecutionFailure('Failed to execute query: $failure')));
    } catch (e) {
      return Failure(domain.QueryExecutionFailure('Failed to execute query: $e'));
    }
  }

  @override
  Future<Result<bool>> testConnection(String connectionString) async {
    final configResult = await _configRepository.getCurrentConfig();
    return await configResult.fold((config) async {
      final localConfig = DatabaseConfig(
        driverName: config.odbcDriverName,
        username: config.username,
        password: config.password ?? '',
        database: config.databaseName,
        server: config.host,
        port: config.port,
        databaseType: _mapDriverNameToDatabaseType(config.driverName),
      );

      final dbConfig = _toConnectDatabaseConfig(localConfig);
      final connectResult = await _connect(dbConfig);
      return await connectResult.fold((command) async {
        final disconnectResult = await _disconnect(command);
        return disconnectResult.fold((_) => Success(true), (failure) => Failure(failure));
      }, (failure) => Failure(failure));
    }, (failure) => Failure(failure));
  }

  @override
  Future<Result<QueryResponse>> executeQuery(QueryRequest request) async {
    final configResult = await _configRepository.getCurrentConfig();

    return await configResult.fold(
      (config) async {
        final localConfig = DatabaseConfig(
          driverName: config.odbcDriverName,
          username: config.username,
          password: config.password ?? '',
          database: config.databaseName,
          server: config.host,
          port: config.port,
          databaseType: _mapDriverNameToDatabaseType(config.driverName),
        );

        final dbConfig = _toConnectDatabaseConfig(localConfig);
        final connectResult = await _connect(dbConfig);

        return await connectResult.fold(
          (command) async {
            final executeResult = await _executeQuery(command, request.query, request.parameters);

            await _disconnect(command);

            return executeResult.fold(
              (data) {
                final response = QueryResponse(
                  id: _uuid.v4(),
                  requestId: request.id,
                  agentId: request.agentId,
                  data: data,
                  affectedRows: data.length,
                  timestamp: DateTime.now(),
                );
                return Success(response);
              },
              (failure) {
                final failureMessage = failure is domain.Failure ? failure.message : failure.toString();
                final errorResponse = QueryResponse(
                  id: _uuid.v4(),
                  requestId: request.id,
                  agentId: request.agentId,
                  data: [],
                  timestamp: DateTime.now(),
                  error: failureMessage,
                );
                return Success(errorResponse);
              },
            );
          },
          (failure) async {
            final failureMessage = failure is domain.Failure ? failure.message : failure.toString();
            final errorResponse = QueryResponse(
              id: _uuid.v4(),
              requestId: request.id,
              agentId: request.agentId,
              data: [],
              timestamp: DateTime.now(),
              error: failureMessage,
            );
            return Success(errorResponse);
          },
        );
      },
      (failure) async {
        final failureMessage = failure is domain.Failure ? failure.message : failure.toString();
        final errorResponse = QueryResponse(
          id: _uuid.v4(),
          requestId: request.id,
          agentId: request.agentId,
          data: [],
          timestamp: DateTime.now(),
          error: failureMessage,
        );
        return Success(errorResponse);
      },
    );
  }

  @override
  Future<Result<int>> executeNonQuery(String query, Map<String, dynamic>? parameters) async {
    final configResult = await _configRepository.getCurrentConfig();

    return await configResult.fold(
      (config) async {
        final localConfig = DatabaseConfig(
          driverName: config.odbcDriverName,
          username: config.username,
          password: config.password ?? '',
          database: config.databaseName,
          server: config.host,
          port: config.port,
          databaseType: _mapDriverNameToDatabaseType(config.driverName),
        );

        final dbConfig = _toConnectDatabaseConfig(localConfig);
        final connectResult = await _connect(dbConfig);

        return await connectResult.fold((command) async {
          final executeResult = await _executeQuery(command, query, parameters);

          await _disconnect(command);

          return executeResult.fold((_) => Success(command.recordCount), (failure) => Failure(failure));
        }, (failure) => Failure(failure));
      },
      (failure) async {
        final failureMessage = failure is domain.Failure ? failure.message : failure.toString();
        return Failure(domain.QueryExecutionFailure('Failed to get config: $failureMessage'));
      },
    );
  }
}
