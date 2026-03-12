import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
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
    this._settings,
  ) : _uuid = const Uuid();
  final OdbcService _service;
  final IAgentConfigRepository _configRepository;
  final IConnectionPool _connectionPool;
  final IRetryManager _retryManager;
  final MetricsCollector _metrics;
  final IOdbcConnectionSettings _settings;
  final Uuid _uuid;
  bool _initialized = false;
  static const int _bufferRetryMarginBytes = 1024 * 1024;
  static const int _maxAutoExpandedBufferBytes = 256 * 1024 * 1024;

  ConnectionOptions get _connectionOptions => ConnectionOptions(
    loginTimeout: Duration(seconds: _settings.loginTimeoutSeconds),
    queryTimeout: ConnectionConstants.defaultQueryTimeout,
    maxResultBufferBytes: _settings.maxResultBufferMb * 1024 * 1024,
    initialResultBufferBytes:
        ConnectionConstants.defaultInitialResultBufferBytes,
    autoReconnectOnConnectionLost: true,
    maxReconnectAttempts: ConnectionConstants.defaultMaxReconnectAttempts,
    reconnectBackoff: ConnectionConstants.defaultReconnectBackoff,
  );

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
        options: _connectionOptions,
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
          (domainFailure) => Failure(
            domain.ConfigurationFailure(
              'Failed to load database configuration: $domainFailure',
            ),
          ),
        );
      },
      (error) => Failure(
        domain.ConnectionFailure('ODBC initialization failed: $error'),
      ),
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

    if (poolResult.isError()) {
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

    final connId = poolResult.getOrNull()!;

    try {
      // Use named parameters if available, otherwise execute without params
      final queryResult =
          request.parameters != null && request.parameters!.isNotEmpty
          ? await _service.executeQueryNamed(
              connId,
              request.query,
              request.parameters!,
            )
          : await _service.executeQuery(
              request.query,
              connectionId: connId,
            );

      if (queryResult.isError()) {
        final error = queryResult.exceptionOrNull()!;
        if (_isInvalidConnectionIdError(error)) {
          await _tryRecoverPoolAfterInvalidConnectionId(connectionString);
          developer.log(
            'Pool returned invalid connection id ($connId), falling back to direct connection',
            name: 'database_gateway',
            level: 900,
          );
          return _executeQueryWithoutPool(request, connectionString, stopwatch);
        }
        if (_isBufferTooSmallError(error)) {
          developer.log(
            'Buffer too small in pooled query, retrying with expanded buffer',
            name: 'database_gateway',
            level: 900,
            error: error,
          );
          return _executeQueryWithoutPool(
            request,
            connectionString,
            stopwatch,
            options: _buildExpandedConnectionOptions(error),
          );
        }
      }

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

          final msg = _odbcErrorMessage(error);
          _metrics.recordFailure(
            queryId: request.id,
            query: request.query,
            executionDuration: stopwatch.elapsed,
            errorMessage: msg,
          );

          final isTimeout = msg.toLowerCase().contains('timeout');
          return Failure(
            domain.QueryExecutionFailure.withContext(
              message: msg,
              context: {
                if (isTimeout) 'timeout': true,
                if (isTimeout) 'timeout_stage': 'sql',
              },
            ),
          );
        },
      );
    } finally {
      // Always release connection back to pool, even if query fails
      await _releaseConnectionSafely(connId);
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

    if (poolResult.isError()) {
      return Failure(
        domain.ConnectionFailure(
          _odbcErrorMessage(poolResult.exceptionOrNull()!),
        ),
      );
    }

    final connId = poolResult.getOrNull()!;

    try {
      // Use named parameters if available
      final result = parameters != null && parameters.isNotEmpty
          ? await _service.executeQueryNamed(
              connId,
              query,
              parameters,
            )
          : await _service.executeQuery(
              query,
              connectionId: connId,
            );

      if (result.isError()) {
        final error = result.exceptionOrNull()!;
        if (_isInvalidConnectionIdError(error)) {
          await _tryRecoverPoolAfterInvalidConnectionId(connectionString);
          developer.log(
            'Pool returned invalid connection id ($connId) for non-query, falling back to direct connection',
            name: 'database_gateway',
            level: 900,
          );
          return _executeNonQueryWithoutPool(
            query,
            parameters,
            connectionString,
          );
        }
      }

      return result.fold(
        (queryResult) => Success(queryResult.rowCount),
        (error) => Failure(
          domain.QueryExecutionFailure(_odbcErrorMessage(error)),
        ),
      );
    } finally {
      // Always release connection back to pool
      await _releaseConnectionSafely(connId);
    }
  }

  Future<Result<QueryResponse>> _executeQueryWithoutPool(
    QueryRequest request,
    String connectionString,
    Stopwatch stopwatch, {
    ConnectionOptions? options,
  }) async {
    final connectResult = await _service.connect(
      connectionString,
      options: options ?? _connectionOptions,
    );

    return connectResult.fold(
      (connection) async {
        try {
          final queryResult =
              request.parameters != null && request.parameters!.isNotEmpty
              ? await _service.executeQueryNamed(
                  connection.id,
                  request.query,
                  request.parameters!,
                )
              : await _service.executeQuery(
                  request.query,
                  connectionId: connection.id,
                );

          return queryResult.fold(
            (qr) {
              final response = _createSuccessResponse(request, qr);
              stopwatch.stop();
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
        } finally {
          await _service.disconnect(connection.id);
        }
      },
      (error) {
        stopwatch.stop();
        _metrics.recordFailure(
          queryId: request.id,
          query: request.query,
          executionDuration: stopwatch.elapsed,
          errorMessage: _odbcErrorMessage(error),
        );
        return Failure(domain.ConnectionFailure(_odbcErrorMessage(error)));
      },
    );
  }

  Future<Result<int>> _executeNonQueryWithoutPool(
    String query,
    Map<String, dynamic>? parameters,
    String connectionString,
  ) async {
    final connectResult = await _service.connect(
      connectionString,
      options: _connectionOptions,
    );

    return connectResult.fold(
      (connection) async {
        try {
          final result = parameters != null && parameters.isNotEmpty
              ? await _service.executeQueryNamed(
                  connection.id,
                  query,
                  parameters,
                )
              : await _service.executeQuery(
                  query,
                  connectionId: connection.id,
                );

          return result.fold(
            (queryResult) => Success(queryResult.rowCount),
            (error) => Failure(
              domain.QueryExecutionFailure(_odbcErrorMessage(error)),
            ),
          );
        } finally {
          await _service.disconnect(connection.id);
        }
      },
      (error) => Failure(domain.ConnectionFailure(_odbcErrorMessage(error))),
    );
  }

  Future<void> _releaseConnectionSafely(String connectionId) async {
    final releaseResult = await _connectionPool.release(connectionId);
    if (releaseResult.isSuccess()) {
      return;
    }

    final releaseError = releaseResult.exceptionOrNull()!;
    developer.log(
      'Failed to release pooled connection: $connectionId',
      name: 'database_gateway',
      level: 900,
      error: releaseError,
    );
  }

  ConnectionOptions _buildExpandedConnectionOptions(Object error) {
    final currentBufferBytes = _settings.maxResultBufferMb * 1024 * 1024;
    final expandedBufferBytes = _calculateExpandedBufferBytes(error);
    final initialResultBufferBytes =
        expandedBufferBytes <
            ConnectionConstants.defaultInitialResultBufferBytes
        ? expandedBufferBytes
        : ConnectionConstants.defaultInitialResultBufferBytes;

    developer.log(
      'Expanding max result buffer for retry: '
      '$currentBufferBytes -> $expandedBufferBytes bytes',
      name: 'database_gateway',
      level: 800,
    );

    return ConnectionOptions(
      loginTimeout: Duration(seconds: _settings.loginTimeoutSeconds),
      queryTimeout: ConnectionConstants.defaultQueryTimeout,
      maxResultBufferBytes: expandedBufferBytes,
      initialResultBufferBytes: initialResultBufferBytes,
      autoReconnectOnConnectionLost: true,
      maxReconnectAttempts: ConnectionConstants.defaultMaxReconnectAttempts,
      reconnectBackoff: ConnectionConstants.defaultReconnectBackoff,
    );
  }

  int _calculateExpandedBufferBytes(Object error) {
    final currentBufferBytes = _settings.maxResultBufferMb * 1024 * 1024;
    final requiredBufferBytes = _extractRequiredBufferBytes(error);

    if (requiredBufferBytes == null) {
      final doubledBuffer = currentBufferBytes * 2;
      if (doubledBuffer > _maxAutoExpandedBufferBytes) {
        return _maxAutoExpandedBufferBytes;
      }
      return doubledBuffer;
    }

    final withMargin = requiredBufferBytes + _bufferRetryMarginBytes;
    if (withMargin > _maxAutoExpandedBufferBytes) {
      return _maxAutoExpandedBufferBytes;
    }
    if (withMargin < currentBufferBytes) {
      return currentBufferBytes;
    }
    return withMargin;
  }

  int? _extractRequiredBufferBytes(Object error) {
    final message = _odbcErrorMessage(error);
    final match = RegExp(
      r'need\s+(\d+)\s+bytes',
      caseSensitive: false,
    ).firstMatch(message);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1) ?? '');
  }

  Future<void> _tryRecoverPoolAfterInvalidConnectionId(
    String connectionString,
  ) async {
    final recycleResult = await _connectionPool.recycle(connectionString);
    if (recycleResult.isSuccess()) {
      developer.log(
        'Pool recycled after invalid connection id',
        name: 'database_gateway',
        level: 800,
      );
      return;
    }

    developer.log(
      'Failed to recycle pool after invalid connection id',
      name: 'database_gateway',
      level: 900,
      error: recycleResult.exceptionOrNull(),
    );
  }

  bool _isInvalidConnectionIdError(Object error) {
    final message = _odbcErrorMessage(error).toLowerCase();

    if (error is ValidationError) {
      return message.contains('invalid connection id');
    }

    if (error is ConnectionError) {
      if (error.nativeCode == 100000) {
        return true;
      }
      return message.contains('invalid connection id');
    }

    if (error is OdbcError || error is QueryError) {
      return message.contains('invalid connection id');
    }

    return message.contains('invalid connection id');
  }

  bool _isBufferTooSmallError(Object error) {
    final message = _odbcErrorMessage(error).toLowerCase();
    return message.contains('buffer too small');
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
}
