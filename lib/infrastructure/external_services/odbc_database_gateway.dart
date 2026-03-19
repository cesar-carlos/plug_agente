import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/infrastructure/builders/odbc_connection_builder.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class _PreparedQueryExecution {
  const _PreparedQueryExecution({
    required this.sql,
    required this.parameters,
  });

  final String sql;
  final Map<String, dynamic>? parameters;
}

class _QueryExecutionOutcome {
  const _QueryExecutionOutcome.success(this.response) : error = null;

  const _QueryExecutionOutcome.failure(this.error) : response = null;

  final QueryResponse? response;
  final Object? error;

  bool get isSuccess => response != null;
}

class _BatchExecutionContext {
  const _BatchExecutionContext({
    required this.connectionId,
    required this.connectionString,
    required this.deadline,
  });

  final String connectionId;
  final String connectionString;
  final DateTime? deadline;
}

class _BatchTransactionStart {
  const _BatchTransactionStart(this.transactionId);

  final int? transactionId;
}

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
  static const _bestEffortCancelDisconnectTimeout = Duration(seconds: 2);

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
          OdbcFailureMapper.mapConnectionError(
            error,
            operation: 'initialize_odbc',
            context: {
              'reason': 'odbc_initialization_failed',
              'user_message':
                  'Não foi possível inicializar o ambiente ODBC neste computador.',
            },
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
    final rawData = _convertQueryResultToMaps(queryResult);
    final paginationResponse = _buildPaginationResponse(
      request.pagination,
      rawData,
    );
    final data = paginationResponse == null
        ? rawData
        : rawData.take(request.pagination!.pageSize).toList();

    return QueryResponse(
      id: _uuid.v4(),
      requestId: request.id,
      agentId: request.agentId,
      data: data,
      affectedRows: data.length,
      timestamp: DateTime.now(),
      columnMetadata: _buildColumnMetadata(queryResult.columns),
      pagination: paginationResponse,
    );
  }

  QueryResponse _createSuccessResponseFromMulti(
    QueryRequest request,
    QueryResultMulti queryResult,
  ) {
    final resultSets = <QueryResultSet>[];
    final items = <QueryResponseItem>[];
    var resultSetIndex = 0;
    var totalAffectedRows = 0;

    for (var itemIndex = 0; itemIndex < queryResult.items.length; itemIndex++) {
      final item = queryResult.items[itemIndex];
      if (item.resultSet != null) {
        final resultSet = QueryResultSet(
          index: resultSetIndex,
          rows: _convertQueryResultToMaps(item.resultSet!),
          rowCount: item.resultSet!.rowCount,
          columnMetadata: _buildColumnMetadata(item.resultSet!.columns),
        );
        resultSets.add(resultSet);
        items.add(
          QueryResponseItem.resultSet(
            index: itemIndex,
            resultSet: resultSet,
          ),
        );
        resultSetIndex++;
        continue;
      }

      final rowCount = item.rowCount ?? 0;
      totalAffectedRows += rowCount;
      items.add(
        QueryResponseItem.rowCount(
          index: itemIndex,
          rowCount: rowCount,
        ),
      );
    }

    final primaryResultSet = resultSets.isNotEmpty
        ? resultSets.first
        : const QueryResultSet(index: 0, rows: [], rowCount: 0);

    return QueryResponse(
      id: _uuid.v4(),
      requestId: request.id,
      agentId: request.agentId,
      data: primaryResultSet.rows,
      affectedRows: totalAffectedRows > 0
          ? totalAffectedRows
          : primaryResultSet.rowCount,
      timestamp: DateTime.now(),
      columnMetadata: primaryResultSet.columnMetadata,
      resultSets: resultSets,
      items: items,
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
              OdbcFailureMapper.mapConnectionError(
                error,
                operation: 'disconnect_test_connection',
              ),
            ),
          );
        },
        (error) {
          developer.log(
            'Connection test failed',
            name: 'database_gateway',
            level: 900,
            error: error,
          );
          return Failure(
            OdbcFailureMapper.mapConnectionError(
              error,
              operation: 'connect_test_connection',
            ),
          );
        },
      );
    }, Failure.new);
  }

  @override
  Future<Result<QueryResponse>> executeQuery(
    QueryRequest request, {
    Duration? timeout,
    String? database,
  }) async {
    developer.log('Executing query ${request.id}', name: 'database_gateway');

    final initResult = await _ensureInitialized();

    return initResult.fold(
      (_) async {
        final configResult = await _configRepository.getCurrentConfig();

        return configResult.fold(
          (config) async {
            final localConfig = _buildDatabaseConfig(config);
            final connectionString = _resolveConnectionString(
              config,
              localConfig,
              databaseOverride: database,
            );

            return _executeQueryWithRetry(
              request,
              connectionString,
              localConfig,
              timeout: timeout,
            );
          },
          (domainFailure) => Failure(
            domain.ConfigurationFailure(
              'Failed to load database configuration: $domainFailure',
            ),
          ),
        );
      },
      (error) => Failure(
        OdbcFailureMapper.mapConnectionError(
          error,
          operation: 'initialize_odbc',
          context: {
            'reason': 'odbc_initialization_failed',
            'user_message':
                'Não foi possível inicializar o ambiente ODBC neste computador.',
          },
        ),
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
    DatabaseConfig databaseConfig, {
    Duration? timeout,
  }) async {
    return _retryManager.execute(
      () => _executeQueryInternal(
        request,
        connectionString,
        databaseConfig,
        timeout: timeout,
      ),
      maxAttempts: 3,
      initialDelayMs: 500,
      backoffMultiplier: 2,
    );
  }

  Future<Result<QueryResponse>> _executeQueryInternal(
    QueryRequest request,
    String connectionString,
    DatabaseConfig databaseConfig, {
    Duration? timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    final preparedExecution = _prepareQueryExecution(request, databaseConfig);
    final queryValidation = _validateQueryExecutionMode(
      request,
      preparedExecution,
    );
    if (queryValidation != null) {
      return Failure(queryValidation);
    }

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

      return Failure(
        OdbcFailureMapper.mapPoolError(
          error,
          operation: 'acquire_connection',
          context: {'query_id': request.id},
        ),
      );
    }

    final connId = poolResult.getOrNull()!;

    try {
      final outcome = await _runQueryExecutionWithTimeout(
        connId: connId,
        request: request,
        preparedExecution: preparedExecution,
        connectionString: connectionString,
        timeout: timeout,
      );

      if (!outcome.isSuccess) {
        final error = outcome.error!;
        if (_isInvalidConnectionIdError(error)) {
          await _tryRecoverPoolAfterInvalidConnectionId(connectionString);
          developer.log(
            'Pool returned invalid connection id ($connId), falling back to direct connection',
            name: 'database_gateway',
            level: 900,
          );
          return _executeQueryWithoutPool(
            request,
            connectionString,
            stopwatch,
            preparedExecution: preparedExecution,
            timeout: timeout,
          );
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
            preparedExecution: preparedExecution,
            timeout: timeout,
          );
        }
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

        return Failure(
          OdbcFailureMapper.mapQueryError(
            error,
            operation: 'execute_query',
            context: {'query_id': request.id},
          ),
        );
      }

      final response = outcome.response!;
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
    } on TimeoutException catch (error) {
      stopwatch.stop();
      _metrics.recordFailure(
        queryId: request.id,
        query: request.query,
        executionDuration: stopwatch.elapsed,
        errorMessage: 'Query execution timeout',
      );
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'SQL execution timeout',
          cause: error,
          context: {
            'timeout': true,
            'timeout_stage': 'sql',
            'stage': 'query',
            'reason': 'query_timeout',
            if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
          },
        ),
      );
    } finally {
      // Always release connection back to pool, even if query fails
      await _releaseConnectionSafely(connId);
    }
  }

  @override
  Future<Result<List<SqlCommandResult>>> executeBatch(
    String agentId,
    List<SqlCommand> commands, {
    String? database,
    SqlExecutionOptions options = const SqlExecutionOptions(),
    Duration? timeout,
  }) async {
    final contextResult = await _prepareBatchExecutionContext(
      database: database,
      timeout: timeout,
    );
    if (contextResult.isError()) {
      return Failure(contextResult.exceptionOrNull()!);
    }

    final context = contextResult.getOrNull()!;
    int? transactionId;
    try {
      final beginResult = await _beginBatchTransactionIfNeeded(
        connectionId: context.connectionId,
        transactionEnabled: options.transaction,
      );
      if (beginResult.isError()) {
        return Failure(beginResult.exceptionOrNull()!);
      }
      transactionId = beginResult.getOrNull()!.transactionId;

      final commandResult = await _executeBatchCommands(
        context: context,
        agentId: agentId,
        commands: commands,
        options: options,
        transactionId: transactionId,
      );
      if (commandResult.isError()) {
        return Failure(commandResult.exceptionOrNull()!);
      }

      if (options.transaction && transactionId != null) {
        final commitResult = await _commitBatchTransaction(
          connectionId: context.connectionId,
          transactionId: transactionId,
        );
        if (commitResult.isError()) {
          return Failure(commitResult.exceptionOrNull()!);
        }
      }

      return commandResult;
    } finally {
      await _releaseConnectionSafely(context.connectionId);
    }
  }

  Future<Result<_BatchExecutionContext>> _prepareBatchExecutionContext({
    required String? database,
    required Duration? timeout,
  }) async {
    final initResult = await _ensureInitialized();
    if (initResult.isError()) {
      final failure = initResult.exceptionOrNull();
      if (failure != null) {
        return Failure(failure);
      }
      return Failure(
        domain.ConnectionFailure('Failed to initialize ODBC for batch'),
      );
    }

    final configResult = await _configRepository.getCurrentConfig();
    if (configResult.isError()) {
      return Failure(
        domain.ConfigurationFailure(
          'Failed to load database configuration for batch execution',
        ),
      );
    }

    final config = configResult.getOrNull()!;
    final localConfig = _buildDatabaseConfig(config);
    final connectionString = _resolveConnectionString(
      config,
      localConfig,
      databaseOverride: database,
    );
    final poolResult = await _connectionPool.acquire(connectionString);
    if (poolResult.isError()) {
      final error = poolResult.exceptionOrNull()!;
      return Failure(
        OdbcFailureMapper.mapPoolError(
          error,
          operation: 'acquire_connection',
          context: {'operation': 'batch_execute'},
        ),
      );
    }

    return Success(
      _BatchExecutionContext(
        connectionId: poolResult.getOrNull()!,
        connectionString: connectionString,
        deadline: timeout == null ? null : DateTime.now().add(timeout),
      ),
    );
  }

  Future<Result<_BatchTransactionStart>> _beginBatchTransactionIfNeeded({
    required String connectionId,
    required bool transactionEnabled,
  }) async {
    if (!transactionEnabled) {
      return const Success(_BatchTransactionStart(null));
    }

    final beginResult = await _service.beginTransaction(connectionId);
    if (beginResult.isError()) {
      final error = beginResult.exceptionOrNull()!;
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Failed to start transaction',
          cause: error,
          context: {
            'reason': 'transaction_failed',
            'operation': 'transaction_begin',
            'error': _odbcErrorMessage(error),
          },
        ),
      );
    }

    return Success(_BatchTransactionStart(beginResult.getOrNull()));
  }

  Future<Result<void>> _commitBatchTransaction({
    required String connectionId,
    required int transactionId,
  }) async {
    final commitResult = await _service.commitTransaction(
      connectionId,
      transactionId,
    );
    if (commitResult.isError()) {
      final error = commitResult.exceptionOrNull()!;
      await _rollbackTransactionIfNeeded(connectionId, transactionId);
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Failed to commit transaction',
          cause: error,
          context: {
            'reason': 'transaction_failed',
            'operation': 'transaction_commit',
            'error': _odbcErrorMessage(error),
          },
        ),
      );
    }

    return const Success(unit);
  }

  Future<Result<List<SqlCommandResult>>> _executeBatchCommands({
    required _BatchExecutionContext context,
    required String agentId,
    required List<SqlCommand> commands,
    required SqlExecutionOptions options,
    required int? transactionId,
  }) async {
    final results = <SqlCommandResult>[];

    for (var i = 0; i < commands.length; i++) {
      final command = commands[i];
      final validation = SqlValidator.validateSqlForExecution(command.sql);
      if (validation.isError()) {
        final failure = validation.exceptionOrNull()! as domain.Failure;
        if (options.transaction) {
          await _rollbackTransactionIfNeeded(
            context.connectionId,
            transactionId,
          );
          return Failure(
            domain.QueryExecutionFailure.withContext(
              message: 'Transaction aborted due to command validation failure',
              cause: failure,
              context: {
                'reason': 'transaction_failed',
                'operation': 'transaction_validation',
                'failedIndex': i,
                'detail': failure.message,
              },
            ),
          );
        }
        results.add(SqlCommandResult.failure(index: i, error: failure.message));
        continue;
      }

      final commandRequest = QueryRequest(
        id: _uuid.v4(),
        agentId: agentId,
        query: command.sql,
        parameters: command.params,
        timestamp: DateTime.now(),
      );

      final remainingTimeout = _remainingTimeout(context.deadline);
      try {
        final outcome = await _runQueryExecutionWithTimeout(
          connId: context.connectionId,
          request: commandRequest,
          preparedExecution: _PreparedQueryExecution(
            sql: command.sql,
            parameters: command.params,
          ),
          connectionString: context.connectionString,
          timeout: remainingTimeout,
        );

        if (!outcome.isSuccess) {
          final error = outcome.error!;
          final failure = OdbcFailureMapper.mapQueryError(
            error,
            operation: 'execute_batch_item',
            context: {
              'command_index': i,
              'transaction': options.transaction,
            },
          );

          if (options.transaction) {
            await _rollbackTransactionIfNeeded(
              context.connectionId,
              transactionId,
            );
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'Transaction aborted due to command failure',
                cause: error,
                context: {
                  'reason': 'transaction_failed',
                  'operation': 'transaction_execute',
                  'failedIndex': i,
                  'detail': failure.message,
                },
              ),
            );
          }

          results.add(
            SqlCommandResult.failure(index: i, error: failure.message),
          );
          continue;
        }

        final response = outcome.response!;
        results.add(
          SqlCommandResult.success(
            index: i,
            rows: response.data,
            rowCount: response.data.length,
            affectedRows: response.affectedRows,
            columnMetadata: response.columnMetadata,
          ),
        );
      } on TimeoutException catch (error) {
        if (options.transaction) {
          await _rollbackTransactionIfNeeded(
            context.connectionId,
            transactionId,
          );
          return Failure(
            domain.QueryExecutionFailure.withContext(
              message: 'Transaction aborted due to timeout',
              cause: error,
              context: {
                'reason': 'transaction_failed',
                'operation': 'transaction_timeout',
                'failedIndex': i,
                'timeout': true,
                'timeout_stage': 'sql',
                'stage': 'batch',
              },
            ),
          );
        }
        return Failure(
          domain.QueryExecutionFailure.withContext(
            message: 'Batch SQL execution timeout',
            cause: error,
            context: {
              'reason': 'query_timeout',
              'timeout': true,
              'timeout_stage': 'sql',
              'stage': 'batch',
            },
          ),
        );
      }
    }

    return Success(results);
  }

  @override
  Future<Result<int>> executeNonQuery(
    String query,
    Map<String, dynamic>? parameters, {
    Duration? timeout,
    String? database,
  }) async {
    final initResult = await _ensureInitialized();

    return initResult.fold(
      (_) async {
        final configResult = await _configRepository.getCurrentConfig();

        return configResult.fold(
          (config) async {
            final localConfig = _buildDatabaseConfig(config);
            final connectionString = _resolveConnectionString(
              config,
              localConfig,
              databaseOverride: database,
            );

            return _executeNonQueryWithRetry(
              query,
              parameters,
              connectionString,
              timeout: timeout,
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
    String connectionString, {
    Duration? timeout,
  }) async {
    return _retryManager.execute(
      () => _executeNonQueryInternal(
        query,
        parameters,
        connectionString,
        timeout: timeout,
      ),
      maxAttempts: 3,
      initialDelayMs: 500,
      backoffMultiplier: 2,
    );
  }

  Future<Result<int>> _executeNonQueryInternal(
    String query,
    Map<String, dynamic>? parameters,
    String connectionString, {
    Duration? timeout,
  }) async {
    final poolResult = await _connectionPool.acquire(connectionString);

    if (poolResult.isError()) {
      return Failure(
        OdbcFailureMapper.mapPoolError(
          poolResult.exceptionOrNull()!,
          operation: 'acquire_connection',
        ),
      );
    }

    final connId = poolResult.getOrNull()!;

    try {
      // Use named parameters if available
      final result = await _runNonQueryWithTimeout(
        connectionId: connId,
        query: query,
        parameters: parameters,
        connectionString: connectionString,
        timeout: timeout,
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
            timeout: timeout,
          );
        }
      }

      return result.fold(
        (queryResult) => Success(queryResult.rowCount),
        (error) => Failure(
          OdbcFailureMapper.mapQueryError(
            error,
            operation: 'execute_non_query',
          ),
        ),
      );
    } on TimeoutException catch (error) {
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Non-query execution timeout',
          cause: error,
          context: {
            'timeout': true,
            'timeout_stage': 'sql',
            'stage': 'query',
            'reason': 'query_timeout',
            if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
          },
        ),
      );
    } finally {
      // Always release connection back to pool
      await _releaseConnectionSafely(connId);
    }
  }

  Future<_QueryExecutionOutcome> _runQueryExecutionWithTimeout({
    required String connId,
    required QueryRequest request,
    required _PreparedQueryExecution preparedExecution,
    required String connectionString,
    Duration? timeout,
  }) async {
    if (timeout == null) {
      return _runQueryExecution(connId, request, preparedExecution);
    }

    try {
      return await _runQueryExecution(
        connId,
        request,
        preparedExecution,
      ).timeout(timeout);
    } on TimeoutException catch (error) {
      await _cancelConnectionForTimeout(connId, connectionString);
      developer.log(
        'SQL query timed out before completion',
        name: 'database_gateway',
        level: 900,
        error: error,
      );
      rethrow;
    }
  }

  Future<Result<QueryResult>> _runNonQueryWithTimeout({
    required String connectionId,
    required String query,
    required String connectionString,
    Map<String, dynamic>? parameters,
    Duration? timeout,
  }) async {
    Future<Result<QueryResult>> run() {
      if (parameters != null && parameters.isNotEmpty) {
        return _service.executeQueryNamed(
          connectionId,
          query,
          parameters,
        );
      }
      return _service.executeQuery(
        query,
        connectionId: connectionId,
      );
    }

    if (timeout == null) {
      return run();
    }

    try {
      return await run().timeout(timeout);
    } on TimeoutException catch (error) {
      await _cancelConnectionForTimeout(connectionId, connectionString);
      developer.log(
        'SQL non-query timed out before completion',
        name: 'database_gateway',
        level: 900,
        error: error,
      );
      rethrow;
    }
  }

  Future<void> _cancelConnectionForTimeout(
    String connectionId,
    String connectionString,
  ) async {
    try {
      final disconnectResult = await _service
          .disconnect(connectionId)
          .timeout(_bestEffortCancelDisconnectTimeout);
      if (disconnectResult.isSuccess()) {
        _metrics.recordTimeoutCancelSuccess();
      } else {
        _metrics.recordTimeoutCancelFailure();
        developer.log(
          'Best-effort timeout cancellation returned error',
          name: 'database_gateway',
          level: 900,
          error: disconnectResult.exceptionOrNull(),
        );
      }
    } on Object catch (error, stackTrace) {
      _metrics.recordTimeoutCancelFailure();
      developer.log(
        'Best-effort timeout cancellation failed',
        name: 'database_gateway',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
    await _tryRecoverPoolAfterInvalidConnectionId(connectionString);
  }

  Duration? _remainingTimeout(DateTime? deadline) {
    if (deadline == null) {
      return null;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('Execution deadline exceeded');
    }
    return remaining;
  }

  Future<void> _rollbackTransactionIfNeeded(
    String connectionId,
    int? transactionId,
  ) async {
    if (transactionId == null) {
      return;
    }
    final rollback = await _service.rollbackTransaction(
      connectionId,
      transactionId,
    );
    if (rollback.isError()) {
      _metrics.recordTransactionRollbackFailure();
      developer.log(
        'Failed to rollback transaction',
        name: 'database_gateway',
        level: 900,
        error: rollback.exceptionOrNull(),
      );
    }
  }

  Future<Result<QueryResponse>> _executeQueryWithoutPool(
    QueryRequest request,
    String connectionString,
    Stopwatch stopwatch, {
    required _PreparedQueryExecution preparedExecution,
    ConnectionOptions? options,
    Duration? timeout,
  }) async {
    final connectResult = await _service.connect(
      connectionString,
      options: options ?? _connectionOptions,
    );

    return connectResult.fold(
      (connection) async {
        try {
          final outcome = await _runQueryExecutionWithTimeout(
            connId: connection.id,
            request: request,
            preparedExecution: preparedExecution,
            connectionString: connectionString,
            timeout: timeout,
          );
          if (!outcome.isSuccess) {
            final error = outcome.error!;
            stopwatch.stop();
            _metrics.recordFailure(
              queryId: request.id,
              query: request.query,
              executionDuration: stopwatch.elapsed,
              errorMessage: _odbcErrorMessage(error),
            );
            return Failure(
              OdbcFailureMapper.mapQueryError(
                error,
                operation: 'execute_query_direct',
                context: {'query_id': request.id},
              ),
            );
          }

          final response = outcome.response!;
          stopwatch.stop();
          _metrics.recordSuccess(
            queryId: request.id,
            query: request.query,
            executionDuration: stopwatch.elapsed,
            rowsAffected: response.affectedRows ?? 0,
            columnCount: response.columnMetadata?.length ?? 0,
          );
          return Success(response);
        } on TimeoutException catch (error) {
          stopwatch.stop();
          _metrics.recordFailure(
            queryId: request.id,
            query: request.query,
            executionDuration: stopwatch.elapsed,
            errorMessage: 'Query execution timeout',
          );
          return Failure(
            domain.QueryExecutionFailure.withContext(
              message: 'SQL execution timeout',
              cause: error,
              context: {
                'timeout': true,
                'timeout_stage': 'sql',
                'stage': 'query',
                'reason': 'query_timeout',
                if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
              },
            ),
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
        return Failure(
          OdbcFailureMapper.mapConnectionError(
            error,
            operation: 'connect_direct',
            context: {'query_id': request.id},
          ),
        );
      },
    );
  }

  Future<Result<int>> _executeNonQueryWithoutPool(
    String query,
    Map<String, dynamic>? parameters,
    String connectionString, {
    Duration? timeout,
  }) async {
    final connectResult = await _service.connect(
      connectionString,
      options: _connectionOptions,
    );

    return connectResult.fold(
      (connection) async {
        try {
          final result = await _runNonQueryWithTimeout(
            connectionId: connection.id,
            query: query,
            parameters: parameters,
            connectionString: connectionString,
            timeout: timeout,
          );

          return result.fold(
            (queryResult) => Success(queryResult.rowCount),
            (error) => Failure(
              OdbcFailureMapper.mapQueryError(
                error,
                operation: 'execute_non_query_direct',
              ),
            ),
          );
        } on TimeoutException catch (error) {
          return Failure(
            domain.QueryExecutionFailure.withContext(
              message: 'Non-query execution timeout',
              cause: error,
              context: {
                'timeout': true,
                'timeout_stage': 'sql',
                'stage': 'query',
                'reason': 'query_timeout',
                if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
              },
            ),
          );
        } finally {
          await _service.disconnect(connection.id);
        }
      },
      (error) => Failure(
        OdbcFailureMapper.mapConnectionError(
          error,
          operation: 'connect_direct',
        ),
      ),
    );
  }

  String _resolveConnectionString(
    Config config,
    DatabaseConfig databaseConfig, {
    String? databaseOverride,
  }) {
    final override = databaseOverride?.trim();
    final resolved = config.resolveConnectionString().trim();

    if (override != null && override.isNotEmpty) {
      final overriddenDatabaseConfig = DatabaseConfig(
        driverName: databaseConfig.driverName,
        username: databaseConfig.username,
        password: databaseConfig.password,
        database: override,
        server: databaseConfig.server,
        port: databaseConfig.port,
        databaseType: databaseConfig.databaseType,
      );
      if (resolved.isNotEmpty) {
        return _overrideDatabaseInConnectionString(resolved, override);
      }
      return OdbcConnectionBuilder.build(overriddenDatabaseConfig);
    }

    if (resolved.isNotEmpty) {
      return resolved;
    }
    return OdbcConnectionBuilder.build(databaseConfig);
  }

  String _overrideDatabaseInConnectionString(
    String connectionString,
    String database,
  ) {
    var updated = connectionString;
    final replacements = <RegExp>[
      RegExp(r'(database)\s*=\s*[^;]*', caseSensitive: false),
      RegExp(r'(dbn)\s*=\s*[^;]*', caseSensitive: false),
      RegExp(r'(initial\s+catalog)\s*=\s*[^;]*', caseSensitive: false),
    ];

    var replaced = false;
    for (final pattern in replacements) {
      if (pattern.hasMatch(updated)) {
        updated = updated.replaceAllMapped(pattern, (match) {
          replaced = true;
          return '${match.group(1)}=$database';
        });
      }
    }

    if (replaced) {
      return updated;
    }

    final suffix = updated.endsWith(';') ? '' : ';';
    return '$updated${suffix}DATABASE=$database';
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

  _PreparedQueryExecution _prepareQueryExecution(
    QueryRequest request,
    DatabaseConfig databaseConfig,
  ) {
    final pagination = request.pagination;
    if (pagination == null) {
      return _PreparedQueryExecution(
        sql: request.query,
        parameters: request.parameters,
      );
    }

    final sql = pagination.usesStableCursor
        ? _buildCursorPaginatedSql(
            request.query,
            databaseConfig.databaseType,
            pagination,
          )
        : _buildOffsetPaginatedSql(
            request.query,
            databaseConfig.databaseType,
            pagination,
          );
    return _PreparedQueryExecution(
      sql: sql,
      parameters: request.parameters,
    );
  }

  domain.ValidationFailure? _validateQueryExecutionMode(
    QueryRequest request,
    _PreparedQueryExecution preparedExecution,
  ) {
    if (!request.expectMultipleResults) {
      return null;
    }
    if (request.pagination != null) {
      return domain.ValidationFailure(
        'Multi-result execution cannot be combined with pagination',
      );
    }
    if (preparedExecution.parameters?.isNotEmpty ?? false) {
      return domain.ValidationFailure(
        'Multi-result execution is not supported with named parameters',
      );
    }
    return null;
  }

  bool _shouldUseMultiResultExecution(
    QueryRequest request,
    _PreparedQueryExecution preparedExecution,
  ) {
    if (!request.expectMultipleResults) {
      return false;
    }
    if (request.pagination != null) {
      return false;
    }
    return !(preparedExecution.parameters?.isNotEmpty ?? false);
  }

  Future<_QueryExecutionOutcome> _runQueryExecution(
    String connectionId,
    QueryRequest request,
    _PreparedQueryExecution preparedExecution,
  ) async {
    if (_shouldUseMultiResultExecution(request, preparedExecution)) {
      final queryResult = await _service.executeQueryMultiFull(
        connectionId,
        preparedExecution.sql,
      );
      return queryResult.fold(
        (success) => _QueryExecutionOutcome.success(
          _createSuccessResponseFromMulti(request, success),
        ),
        _QueryExecutionOutcome.failure,
      );
    }

    final queryResult =
        preparedExecution.parameters != null &&
            preparedExecution.parameters!.isNotEmpty
        ? await _service.executeQueryNamed(
            connectionId,
            preparedExecution.sql,
            preparedExecution.parameters!,
          )
        : await _service.executeQuery(
            preparedExecution.sql,
            connectionId: connectionId,
          );

    return queryResult.fold(
      (success) => _QueryExecutionOutcome.success(
        _createSuccessResponse(request, success),
      ),
      _QueryExecutionOutcome.failure,
    );
  }

  QueryPaginationInfo? _buildPaginationResponse(
    QueryPaginationRequest? pagination,
    List<Map<String, dynamic>> rawData,
  ) {
    if (pagination == null) {
      return null;
    }

    final rawRowCount = rawData.length;
    final hasNextPage = rawRowCount > pagination.pageSize;
    final returnedRows = hasNextPage ? pagination.pageSize : rawRowCount;
    final pageData = rawData.take(returnedRows).toList();
    return QueryPaginationInfo(
      page: pagination.page,
      pageSize: pagination.pageSize,
      returnedRows: returnedRows,
      hasNextPage: hasNextPage,
      hasPreviousPage: pagination.page > 1,
      currentCursor: pagination.cursor,
      nextCursor: hasNextPage ? _buildNextCursor(pagination, pageData) : null,
    );
  }

  String _buildOffsetPaginatedSql(
    String originalSql,
    DatabaseType databaseType,
    QueryPaginationRequest pagination,
  ) {
    final trimmedSql = SqlValidator.stripTopLevelOrderBy(originalSql);
    final orderByClause = pagination.orderBy.isEmpty
        ? null
        : _buildOrderByClause(pagination.orderBy);
    return switch (databaseType) {
      DatabaseType.postgresql =>
        '''
SELECT *
FROM (
  $trimmedSql
) AS plug_paginated_source
${orderByClause != null ? 'ORDER BY $orderByClause' : ''}
LIMIT ${pagination.fetchSizeWithLookAhead} OFFSET ${pagination.offset}
''',
      DatabaseType.sqlServer || DatabaseType.sybaseAnywhere =>
        '''
SELECT *
FROM (
  $trimmedSql
) AS plug_paginated_source
ORDER BY ${orderByClause ?? '(SELECT NULL)'}
OFFSET ${pagination.offset} ROWS FETCH NEXT ${pagination.fetchSizeWithLookAhead} ROWS ONLY
''',
    };
  }

  String _buildCursorPaginatedSql(
    String originalSql,
    DatabaseType databaseType,
    QueryPaginationRequest pagination,
  ) {
    final trimmedSql = SqlValidator.stripTopLevelOrderBy(originalSql);
    final orderByClause = _buildOrderByClause(pagination.orderBy);
    final whereClause = _buildKeysetWhereClause(
      pagination.orderBy,
      pagination.lastRowValues,
      databaseType,
    );

    return switch (databaseType) {
      DatabaseType.postgresql =>
        '''
SELECT *
FROM (
  $trimmedSql
) AS plug_paginated_source
WHERE $whereClause
ORDER BY $orderByClause
LIMIT ${pagination.fetchSizeWithLookAhead}
''',
      DatabaseType.sqlServer || DatabaseType.sybaseAnywhere =>
        '''
SELECT *
FROM (
  $trimmedSql
) AS plug_paginated_source
WHERE $whereClause
ORDER BY $orderByClause
OFFSET 0 ROWS FETCH NEXT ${pagination.fetchSizeWithLookAhead} ROWS ONLY
''',
    };
  }

  String _buildOrderByClause(List<QueryPaginationOrderTerm> orderBy) {
    return orderBy
        .map(
          (term) => '${term.expression}${term.descending ? ' DESC' : ' ASC'}',
        )
        .join(', ');
  }

  String _buildKeysetWhereClause(
    List<QueryPaginationOrderTerm> orderBy,
    List<dynamic> lastRowValues,
    DatabaseType databaseType,
  ) {
    final disjunctions = <String>[];

    for (var i = 0; i < orderBy.length; i++) {
      final conjunctions = <String>[];
      for (var j = 0; j < i; j++) {
        conjunctions.add(
          '${orderBy[j].expression} = '
          '${_toSqlLiteral(lastRowValues[j], databaseType)}',
        );
      }

      final operator = orderBy[i].descending ? '<' : '>';
      conjunctions.add(
        '${orderBy[i].expression} $operator '
        '${_toSqlLiteral(lastRowValues[i], databaseType)}',
      );
      disjunctions.add('(${conjunctions.join(' AND ')})');
    }

    return disjunctions.join(' OR ');
  }

  String? _buildNextCursor(
    QueryPaginationRequest pagination,
    List<Map<String, dynamic>> pageData,
  ) {
    if (pageData.isEmpty) {
      return null;
    }
    if (pagination.orderBy.isEmpty) {
      return null;
    }

    final lastRow = pageData.last;
    final lastRowValues = <dynamic>[];
    for (final term in pagination.orderBy) {
      if (!lastRow.containsKey(term.lookupKey)) {
        developer.log(
          'Unable to derive cursor key "${term.lookupKey}" from page data',
          name: 'database_gateway',
          level: 900,
        );
        return null;
      }
      lastRowValues.add(lastRow[term.lookupKey]);
    }

    return QueryPaginationCursor(
      page: pagination.page + 1,
      pageSize: pagination.pageSize,
      queryHash: pagination.queryHash,
      orderBy: pagination.orderBy,
      lastRowValues: lastRowValues,
    ).toToken();
  }

  String _toSqlLiteral(dynamic value, DatabaseType databaseType) {
    if (value == null) {
      throw StateError('Cursor pagination does not support null order values');
    }
    if (value is num) {
      return value.toString();
    }
    if (value is bool) {
      return switch (databaseType) {
        DatabaseType.postgresql => value ? 'TRUE' : 'FALSE',
        DatabaseType.sqlServer ||
        DatabaseType.sybaseAnywhere => value ? '1' : '0',
      };
    }
    if (value is DateTime) {
      return "'${value.toUtc().toIso8601String().replaceAll("'", "''")}'";
    }
    final stringValue = value.toString().replaceAll("'", "''");
    return "'$stringValue'";
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

  List<Map<String, dynamic>> _buildColumnMetadata(List<String> columns) {
    return columns
        .map((column) => <String, dynamic>{'name': column})
        .toList(growable: false);
  }
}
