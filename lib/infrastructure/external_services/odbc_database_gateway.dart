import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/infrastructure/builders/odbc_connection_builder.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

/// ODBC Database Gateway using odbc_fast package.
///
/// This implementation provides:
/// - Native Rust engine for better performance
/// - Async API (non-blocking) for Flutter
/// - Simplified code (no manual column extraction)
/// - Built-in error handling with Result types
/// - Connection pooling for reduced overhead
/// - Performance metrics collection
class OdbcDatabaseGateway implements IDatabaseGateway {
  OdbcDatabaseGateway(
    this._configRepository,
    this._service,
    this._connectionPool,
    this._retryManager,
    this._metrics,
  ) : _uuid = const Uuid();
  final OdbcService _service;
  final IAgentConfigRepository _configRepository;
  final IConnectionPool _connectionPool;
  final IRetryManager _retryManager;
  final MetricsCollector _metrics;
  final Uuid _uuid;
  bool _initialized = false;

  /// Ensures ODBC environment is initialized before operations.
  Future<Result<void>> _ensureInitialized() async {
    if (_initialized) {
      return const Success(unit);
    }

    developer.log('Initializing ODBC environment', name: 'database_gateway');

    final initResult = await _service.initialize();
    return initResult.fold(
      (_) {
        _initialized = true;
        developer.log(
          'ODBC initialized successfully',
          name: 'database_gateway',
          level: 500,
        );
        return const Success(unit);
      },
      (error) {
        developer.log(
          'ODBC initialization failed',
          name: 'database_gateway',
          level: 1000,
          error: error,
        );
        return Failure(
          domain.ConnectionFailure(
            'Failed to initialize ODBC: ${_odbcErrorMessage(error)}',
          ),
        );
      },
    );
  }

  String _odbcErrorMessage(Object error) {
    if (error is OdbcError) {
      return error.message;
    }
    return error.toString();
  }

  QueryResponse _createSuccessResponse(
    QueryRequest request,
    QueryResult queryResult,
  ) {
    return QueryResponse(
      id: _uuid.v4(),
      requestId: request.id,
      agentId: request.agentId,
      data: _convertQueryResultToMaps(queryResult),
      affectedRows: queryResult.rowCount,
      timestamp: DateTime.now(),
    );
  }

  QueryResponse _createErrorResponse(QueryRequest request, String error) {
    return QueryResponse(
      id: _uuid.v4(),
      requestId: request.id,
      agentId: request.agentId,
      data: [],
      timestamp: DateTime.now(),
      error: error,
    );
  }

  @override
  Future<Result<bool>> testConnection(String connectionString) async {
    final initResult = await _ensureInitialized();

    return initResult.fold((_) async {
      if (connectionString.trim().isEmpty) {
        return Failure(
          domain.ValidationFailure('Connection string cannot be empty'),
        );
      }

      final connResult = await _service.connect(
        connectionString,
      );

      return connResult.fold(
        (connection) async {
          final disconnectResult = await _service.disconnect(
            connection.id,
          );
          return disconnectResult.fold(
            (_) => const Success(true),
            (error) => Failure(
              domain.ConnectionFailure(
                'Failed to disconnect: ${_odbcErrorMessage(error)}',
              ),
            ),
          );
        },
        (error) => Failure(domain.ConnectionFailure(_odbcErrorMessage(error))),
      );
    }, Failure.new);
  }

  @override
  Future<Result<QueryResponse>> executeQuery(QueryRequest request) async {
    developer.log('Executing query ${request.id}', name: 'database_gateway');

    final initResult = await _ensureInitialized();

    return initResult.fold(
      (_) async {
        final configResult = await _configRepository.getCurrentConfig();

        return configResult.fold(
          (config) async {
            final localConfig = _buildDatabaseConfig(config);
            final connectionString = OdbcConnectionBuilder.build(localConfig);

            return _executeQueryWithRetry(request, connectionString);
          },
          (domainFailure) {
            return Success(
              _createErrorResponse(request, domainFailure.toString()),
            );
          },
        );
      },
      (error) {
        return Success(_createErrorResponse(request, error.toString()));
      },
    );
  }

  DatabaseConfig _buildDatabaseConfig(Config config) {
    return DatabaseConfig(
      driverName: config.odbcDriverName,
      username: config.username,
      password: config.password ?? '',
      database: config.databaseName,
      server: config.host,
      port: config.port,
      databaseType: _mapDriverNameToDatabaseType(config.driverName),
    );
  }

  Future<Result<QueryResponse>> _executeQueryWithRetry(
    QueryRequest request,
    String connectionString,
  ) async {
    return _retryManager.execute(
      () => _executeQueryInternal(request, connectionString),
      maxAttempts: 3,
      initialDelayMs: 500,
      backoffMultiplier: 2,
    );
  }

  Future<Result<QueryResponse>> _executeQueryInternal(
    QueryRequest request,
    String connectionString,
  ) async {
    final stopwatch = Stopwatch()..start();

    final poolResult = await _connectionPool.acquire(connectionString);

    if (poolResult.isSuccess()) {
      final connId = poolResult.getOrNull()!;

      final queryResult = await _service.executeQuery(connId, request.query);

      await _connectionPool.release(connId);

      return queryResult.fold(
        (qr) {
          final response = _createSuccessResponse(request, qr);
          stopwatch.stop();

          developer.log(
            'Query ${request.id} completed in ${stopwatch.elapsedMilliseconds}ms',
            name: 'database_gateway',
            level: 500,
          );

          _metrics.recordSuccess(
            queryId: request.id,
            query: request.query,
            executionDuration: stopwatch.elapsed,
            rowsAffected: response.affectedRows ?? 0,
            columnCount: response.columnMetadata?.length ?? 0,
          );

          return Success(response);
        },
        (error) {
          stopwatch.stop();

          developer.log(
            'Query ${request.id} failed',
            name: 'database_gateway',
            level: 1000,
            error: error,
          );

          _metrics.recordFailure(
            queryId: request.id,
            query: request.query,
            executionDuration: stopwatch.elapsed,
            errorMessage: _odbcErrorMessage(error),
          );

          return Failure(
            domain.QueryExecutionFailure(_odbcErrorMessage(error)),
          );
        },
      );
    } else {
      stopwatch.stop();

      final error = poolResult.exceptionOrNull()!;

      developer.log(
        'Failed to acquire connection for query ${request.id}',
        name: 'database_gateway',
        level: 1000,
        error: error,
      );

      _metrics.recordFailure(
        queryId: request.id,
        query: request.query,
        executionDuration: stopwatch.elapsed,
        errorMessage: _odbcErrorMessage(error),
      );

      return Failure(domain.ConnectionFailure(_odbcErrorMessage(error)));
    }
  }

  @override
  Future<Result<int>> executeNonQuery(
    String query,
    Map<String, dynamic>? parameters,
  ) async {
    final initResult = await _ensureInitialized();

    return initResult.fold(
      (_) async {
        final configResult = await _configRepository.getCurrentConfig();

        return configResult.fold(
          (config) async {
            final localConfig = _buildDatabaseConfig(config);
            final connectionString = OdbcConnectionBuilder.build(localConfig);

            return _executeNonQueryWithRetry(
              query,
              parameters,
              connectionString,
            );
          },
          (domainFailure) => Failure(
            domain.ConfigurationFailure(
              'Failed to get config: $domainFailure',
            ),
          ),
        );
      },
      Failure.new,
    );
  }

  Future<Result<int>> _executeNonQueryWithRetry(
    String query,
    Map<String, dynamic>? parameters,
    String connectionString,
  ) async {
    return _retryManager.execute(
      () => _executeNonQueryInternal(query, parameters, connectionString),
      maxAttempts: 3,
      initialDelayMs: 500,
      backoffMultiplier: 2,
    );
  }

  Future<Result<int>> _executeNonQueryInternal(
    String query,
    Map<String, dynamic>? parameters,
    String connectionString,
  ) async {
    final poolResult = await _connectionPool.acquire(connectionString);

    return poolResult.fold(
      (connId) async {
        final result = parameters != null && parameters.isNotEmpty
            ? await _service.executeQueryParams(
                connId,
                query,
                _paramsToList(parameters),
              )
            : await _service.executeQuery(connId, query);

        await _connectionPool.release(connId);

        return result.fold(
          (queryResult) => Success(queryResult.rowCount),
          (error) => Failure(
            domain.QueryExecutionFailure(_odbcErrorMessage(error)),
          ),
        );
      },
      (error) => Failure(domain.ConnectionFailure(_odbcErrorMessage(error))),
    );
  }

  DatabaseType _mapDriverNameToDatabaseType(String driverName) {
    return switch (driverName) {
      'SQL Server' => DatabaseType.sqlServer,
      'PostgreSQL' => DatabaseType.postgresql,
      'SQL Anywhere' => DatabaseType.sybaseAnywhere,
      _ => DatabaseType.sqlServer,
    };
  }

  List<Map<String, dynamic>> _convertQueryResultToMaps(QueryResult result) {
    return result.rows.map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < result.columns.length; i++) {
        map[result.columns[i]] = row[i];
      }
      return map;
    }).toList();
  }

  List<dynamic> _paramsToList(Map<String, dynamic> params) {
    return params.values.toList();
  }
}
