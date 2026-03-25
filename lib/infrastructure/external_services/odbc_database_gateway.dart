import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/utils/sql_row_truncation.dart';
import 'package:plug_agente/domain/entities/config.dart';
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
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_result_mapper.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_options_builder.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

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
    this.ownedConnection = false,
  });

  final String connectionId;
  final String connectionString;
  final DateTime? deadline;

  /// When true, [connectionId] was obtained via [OdbcService.connect] and must
  /// be disconnected; otherwise it is a pooled handle and must be released.
  final bool ownedConnection;
}

class _BatchTransactionStart {
  const _BatchTransactionStart(this.transactionId);

  final int? transactionId;
}

class _BatchMultiResultFastPath {
  const _BatchMultiResultFastPath({
    required this.agentId,
    required this.sql,
    required this.commandCount,
  });

  final String agentId;
  final String sql;
  final int commandCount;
}

/// ODBC Database Gateway using odbc_fast package.
///
/// This implementation provides:
/// - Native Rust engine for better performance
/// - Async API (non-blocking) for Flutter
/// - Simplified code (no manual column extraction)
/// - Built-in error handling with Result types
/// - Connection pooling for reduced overhead
/// - Performance metrics collection ([MetricsCollector] pool counters count
///   each acquire/release attempt, not deduplicated across retries)
class OdbcDatabaseGateway implements IDatabaseGateway {
  OdbcDatabaseGateway(
    this._configRepository,
    this._service,
    this._connectionPool,
    this._retryManager,
    this._metrics,
    this._settings, {
    FeatureFlags? featureFlags,
  }) : _featureFlags = featureFlags,
       _uuid = const Uuid();
  final OdbcService _service;
  final IAgentConfigRepository _configRepository;
  final IConnectionPool _connectionPool;
  final IRetryManager _retryManager;
  final MetricsCollector _metrics;
  final IOdbcConnectionSettings _settings;
  final FeatureFlags? _featureFlags;
  final Uuid _uuid;
  bool _initialized = false;
  Config? _cachedConfig;
  DateTime? _cachedConfigFetchedAt;
  Future<Result<Config>>? _configLoadInFlight;
  static const _bestEffortCancelDisconnectTimeout = Duration(seconds: 2);
  static const _configCacheTtl = Duration(seconds: 60);
  static const int _multiResultSqlLogPreviewChars = 120;
  final Set<String> _leaseWarmupKeys = <String>{};
  static final RegExp _previewSqlWhitespaceCollapse = RegExp(r'\s+');
  static final List<RegExp> _connectionStringDatabasePatterns = [
    RegExp(r'(database)\s*=\s*[^;]*', caseSensitive: false),
    RegExp(r'(dbn)\s*=\s*[^;]*', caseSensitive: false),
    RegExp(r'(initial\s+catalog)\s*=\s*[^;]*', caseSensitive: false),
  ];

  void _scheduleLeasePoolWarmupIfNeeded(String connectionString) {
    if (_settings.useNativeOdbcPool || _settings.leaseWarmupCount <= 0) {
      return;
    }
    if (!_leaseWarmupKeys.add(connectionString)) {
      return;
    }
    unawaited(
      _connectionPool.warmIdleLeases(connectionString).then((Result<void> r) {
        _leaseWarmupKeys.remove(connectionString);
      }),
    );
  }

  Future<Result<String>> _acquireFromPool(String connectionString) async {
    _scheduleLeasePoolWarmupIfNeeded(connectionString);
    return _connectionPool.acquire(connectionString);
  }

  static String _previewSqlForLog(String sql) {
    final collapsed = sql.replaceAll(_previewSqlWhitespaceCollapse, ' ').trim();
    if (collapsed.length <= _multiResultSqlLogPreviewChars) {
      return collapsed;
    }
    return '${collapsed.substring(0, _multiResultSqlLogPreviewChars)}…';
  }

  ConnectionOptions get _connectionOptions => OdbcConnectionOptionsBuilder.forQueryExecution(_settings);

  Future<Result<Connection>> _connectDirect(
    String connectionString, {
    ConnectionOptions? options,
  }) async {
    final stopwatch = Stopwatch()..start();
    final result = await _service.connect(
      connectionString,
      options: options ?? _connectionOptions,
    );
    stopwatch.stop();
    _metrics.recordDirectConnectionConnectLatency(stopwatch.elapsed);
    return result;
  }

  Future<Result<void>> _disconnectDirect(String connectionId) async {
    final stopwatch = Stopwatch()..start();
    final result = await _service.disconnect(connectionId);
    stopwatch.stop();
    _metrics.recordDirectConnectionDisconnectLatency(stopwatch.elapsed);
    return result.fold(
      (_) => const Success(unit),
      (error) => Failure(
        OdbcFailureMapper.mapConnectionError(
          error,
          operation: 'disconnect_direct',
        ),
      ),
    );
  }

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
              'user_message': 'Não foi possível inicializar o ambiente ODBC neste computador.',
            },
          ),
        );
      },
    );
  }

  Future<Result<Config>> _getCurrentConfig() async {
    final now = DateTime.now();
    final cached = _cachedConfig;
    final cachedAt = _cachedConfigFetchedAt;
    if (cached != null && cachedAt != null && now.difference(cachedAt) <= _configCacheTtl) {
      return Success(cached);
    }

    final inFlight = _configLoadInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final loadFuture = _loadAndCacheCurrentConfig();
    _configLoadInFlight = loadFuture;
    try {
      return await loadFuture;
    } finally {
      if (identical(_configLoadInFlight, loadFuture)) {
        _configLoadInFlight = null;
      }
    }
  }

  Future<Result<Config>> _loadAndCacheCurrentConfig() async {
    final configResult = await _configRepository.getCurrentConfig();
    return configResult.fold(
      (config) {
        _cachedConfig = config;
        _cachedConfigFetchedAt = DateTime.now();
        return Success(config);
      },
      Failure.new,
    );
  }

  @override
  void invalidateConfigCache() {
    _cachedConfig = null;
    _cachedConfigFetchedAt = null;
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
    final rawData = OdbcGatewayQueryResultMapper.convertQueryResultToMaps(
      queryResult,
    );
    final paginationResponse = OdbcGatewayQueryResultMapper.buildPaginationResponse(
      request.pagination,
      rawData,
    );
    final data = paginationResponse == null ? rawData : rawData.take(request.pagination!.pageSize).toList();

    return QueryResponse(
      id: _uuid.v4(),
      requestId: request.id,
      agentId: request.agentId,
      data: data,
      affectedRows: data.length,
      timestamp: DateTime.now(),
      columnMetadata: OdbcGatewayQueryResultMapper.buildColumnMetadata(
        queryResult.columns,
      ),
      pagination: paginationResponse,
    );
  }

  /// Builds a multi-result [QueryResponse]. Top-level [QueryResponse.affectedRows]
  /// sums row-count items when present; otherwise falls back to the first result
  /// set row count (legacy single-field compatibility for RPC).
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
          rows: OdbcGatewayQueryResultMapper.convertQueryResultToMaps(
            item.resultSet!,
          ),
          rowCount: item.resultSet!.rowCount,
          columnMetadata: OdbcGatewayQueryResultMapper.buildColumnMetadata(
            item.resultSet!.columns,
          ),
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
      affectedRows: totalAffectedRows > 0 ? totalAffectedRows : primaryResultSet.rowCount,
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

      final connResult = await _connectDirect(connectionString);

      return connResult.fold(
        (connection) async {
          final disconnectResult = await _disconnectDirect(connection.id);
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
    final initResult = await _ensureInitialized();

    return initResult.fold(
      (_) async {
        final configResult = await _getCurrentConfig();

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
            'user_message': 'Não foi possível inicializar o ambiente ODBC neste computador.',
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
    final paginationValidation = OdbcGatewayQueryPreparation.validatePaginationForDatabase(
      request,
      databaseConfig.databaseType,
    );
    if (paginationValidation != null) {
      return Failure(paginationValidation);
    }

    final preparedExecution = OdbcGatewayQueryPreparation.prepareQueryExecution(
      request,
      databaseConfig,
    );
    final queryValidation = OdbcGatewayQueryPreparation.validateQueryExecutionMode(
      request,
      preparedExecution,
    );
    if (queryValidation != null) {
      return Failure(queryValidation);
    }

    OdbcGatewayQueryPreparation.maybeLogPaginatedSqlRewrite(
      featureFlags: _featureFlags,
      request: request,
      databaseConfig: databaseConfig,
      preparedExecution: preparedExecution,
    );

    final poolResult = await _acquireFromPool(connectionString);

    if (poolResult.isError()) {
      stopwatch.stop();
      final error = poolResult.exceptionOrNull()!;

      developer.log(
        'Failed to acquire connection for query ${request.id}',
        name: 'database_gateway',
        level: 1000,
        error: error,
      );

      _metrics.recordConnectionPoolAcquireFailure();
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
        if (OdbcGatewayBufferExpansion.messageIndicatesBufferTooSmall(
          _odbcErrorMessage(error),
        )) {
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
      if (_isVacuousMultiResultResponse(request, response)) {
        _metrics.recordMultiResultPoolVacuousFallback();
        developer.log(
          'Pooled executeQueryMultiFull returned no rows or row-count items; '
          'retrying on a direct connection (pool/driver quirk) '
          '(query_id=${request.id}, '
          'sql_preview=${_previewSqlForLog(preparedExecution.sql)})',
          name: 'database_gateway',
          level: 800,
        );
        return _executeQueryWithoutPool(
          request,
          connectionString,
          stopwatch,
          preparedExecution: preparedExecution,
          timeout: timeout,
          afterVacuousPooledMulti: true,
        );
      }

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
    for (var attempt = 0; attempt < 2; attempt++) {
      final contextResult = await _prepareBatchExecutionContext(
        database: database,
        timeout: timeout,
        useOwnedConnection: options.transaction,
      );
      if (contextResult.isError()) {
        return Failure(contextResult.exceptionOrNull()!);
      }

      final context = contextResult.getOrNull()!;
      var recycleAfterRelease = false;
      int? transactionId;
      try {
        final beginResult = await _beginBatchTransactionIfNeeded(
          connectionId: context.connectionId,
          transactionEnabled: options.transaction,
        );
        if (beginResult.isError()) {
          final beginFailure = beginResult.exceptionOrNull()! as domain.Failure;
          if (options.transaction && attempt == 0 && _queryFailureIndicatesInvalidConnectionId(beginFailure)) {
            recycleAfterRelease = true;
          } else {
            return Failure(beginFailure);
          }
        } else {
          if (options.transaction && context.ownedConnection) {
            _metrics.recordTransactionalBatchDirectPath();
            developer.log(
              'Transactional executeBatch uses direct ODBC connection (pool bypass)',
              name: 'database_gateway',
              level: 800,
            );
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
        }
      } finally {
        await _releaseBatchConnection(context);
      }

      if (recycleAfterRelease) {
        continue;
      }
    }

    // Invariant: every loop iteration returns from inside the try block or
    // continues after a recycled invalid pooled handle.
    // coverage:ignore-start
    throw StateError(
      'executeBatch: retry loop finished without returning a result',
    );
    // coverage:ignore-end
  }

  Future<void> _releaseBatchConnection(_BatchExecutionContext context) async {
    if (context.ownedConnection) {
      await _disconnectDirect(context.connectionId);
      return;
    }
    await _releaseConnectionSafely(context.connectionId);
  }

  Future<Result<_BatchExecutionContext>> _prepareBatchExecutionContext({
    required String? database,
    required Duration? timeout,
    required bool useOwnedConnection,
  }) async {
    final initResult = await _ensureInitialized();
    if (initResult.isError()) {
      return Failure(initResult.exceptionOrNull()!);
    }

    final configResult = await _getCurrentConfig();
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
    final deadline = timeout == null ? null : DateTime.now().add(timeout);

    if (useOwnedConnection) {
      final connectResult = await _connectDirect(connectionString);
      return connectResult.fold(
        (connection) {
          return Success(
            _BatchExecutionContext(
              connectionId: connection.id,
              connectionString: connectionString,
              deadline: deadline,
              ownedConnection: true,
            ),
          );
        },
        (error) => Failure(
          OdbcFailureMapper.mapConnectionError(
            error,
            operation: 'connect_direct',
            context: {
              'operation': 'batch_execute',
              'transaction': true,
            },
          ),
        ),
      );
    }

    final poolResult = await _acquireFromPool(connectionString);
    if (poolResult.isError()) {
      final error = poolResult.exceptionOrNull()!;
      _metrics.recordConnectionPoolAcquireFailure();
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
        deadline: deadline,
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

  _BatchMultiResultFastPath? _buildBatchMultiResultFastPath(
    String agentId,
    List<SqlCommand> commands,
    SqlExecutionOptions options,
  ) {
    if (options.transaction || commands.length < 2) {
      return null;
    }

    final sqlParts = <String>[];
    for (final command in commands) {
      if (command.params != null && command.params!.isNotEmpty) {
        return null;
      }
      final validation = SqlValidator.validateSqlForExecution(command.sql);
      if (validation.isError()) {
        return null;
      }
      final normalized = command.sql.trimLeft().toLowerCase();
      if (!normalized.startsWith('select ') && !normalized.startsWith('with ')) {
        return null;
      }
      sqlParts.add(command.sql.trim().replaceFirst(RegExp(r';+\s*$'), ''));
    }

    return _BatchMultiResultFastPath(
      agentId: agentId,
      sql: sqlParts.join(';\n'),
      commandCount: commands.length,
    );
  }

  Future<Result<List<SqlCommandResult>>?> _tryExecuteBatchViaMultiResult({
    required _BatchExecutionContext context,
    required _BatchMultiResultFastPath fastPath,
    required SqlExecutionOptions options,
  }) async {
    final request = QueryRequest(
      id: _uuid.v4(),
      agentId: fastPath.agentId,
      query: fastPath.sql,
      timestamp: DateTime.now(),
      expectMultipleResults: true,
    );

    try {
      final outcome = await _runQueryExecutionWithTimeout(
        connId: context.connectionId,
        request: request,
        preparedExecution: OdbcPreparedQueryExecution(
          sql: fastPath.sql,
          parameters: null,
        ),
        connectionString: context.connectionString,
        timeout: _remainingTimeout(context.deadline),
      );
      if (!outcome.isSuccess) {
        developer.log(
          'Batch multi_result fast-path failed; falling back to sequential execution',
          name: 'database_gateway',
          level: 800,
          error: outcome.error,
        );
        return null;
      }

      final response = outcome.response!;
      if (_isVacuousMultiResultResponse(request, response) ||
          response.resultSets.length != fastPath.commandCount ||
          response.items.any((QueryResponseItem item) => item.isRowCount)) {
        developer.log(
          'Batch multi_result fast-path returned unexpected payload; falling back to sequential execution',
          name: 'database_gateway',
          level: 800,
        );
        return null;
      }

      return Success(
        response.resultSets
            .map((QueryResultSet resultSet) {
              final limitedRows = truncateSqlResultRows(
                resultSet.rows,
                options.maxRows,
              );
              return SqlCommandResult.success(
                index: resultSet.index,
                rows: limitedRows,
                rowCount: limitedRows.length,
                affectedRows: resultSet.affectedRows,
                columnMetadata: resultSet.columnMetadata,
              );
            })
            .toList(growable: false),
      );
    } on TimeoutException {
      rethrow;
    } on Object catch (error, stackTrace) {
      developer.log(
        'Batch multi_result fast-path threw; falling back to sequential execution',
        name: 'database_gateway',
        level: 800,
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<Result<List<SqlCommandResult>>> _executeBatchCommands({
    required _BatchExecutionContext context,
    required String agentId,
    required List<SqlCommand> commands,
    required SqlExecutionOptions options,
    required int? transactionId,
  }) async {
    final fastPath = _buildBatchMultiResultFastPath(
      agentId,
      commands,
      options,
    );
    if (fastPath != null) {
      final fastPathResult = await _tryExecuteBatchViaMultiResult(
        context: context,
        fastPath: fastPath,
        options: options,
      );
      if (fastPathResult != null) {
        return fastPathResult;
      }
    }

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
          preparedExecution: OdbcPreparedQueryExecution(
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
        final limitedRows = truncateSqlResultRows(
          response.data,
          options.maxRows,
        );
        results.add(
          SqlCommandResult.success(
            index: i,
            rows: limitedRows,
            rowCount: limitedRows.length,
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
        final configResult = await _getCurrentConfig();

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
    final poolResult = await _acquireFromPool(connectionString);

    if (poolResult.isError()) {
      _metrics.recordConnectionPoolAcquireFailure();
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
    required OdbcPreparedQueryExecution preparedExecution,
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
      final disconnectResult = await _disconnectDirect(
        connectionId,
      ).timeout(_bestEffortCancelDisconnectTimeout);
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
    required OdbcPreparedQueryExecution preparedExecution,
    ConnectionOptions? options,
    Duration? timeout,
    bool afterVacuousPooledMulti = false,
  }) async {
    final connectResult = await _connectDirect(
      connectionString,
      options: options,
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
          if (afterVacuousPooledMulti && _isVacuousMultiResultResponse(request, response)) {
            _metrics.recordMultiResultDirectStillVacuous();
            developer.log(
              'Direct connection multi-result still vacuous after pooled empty '
              'payload (query_id=${request.id}, '
              'sql_preview=${_previewSqlForLog(preparedExecution.sql)})',
              name: 'database_gateway',
              level: 800,
            );
          }
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
          await _disconnectDirect(connection.id);
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
    final connectResult = await _connectDirect(connectionString);

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
          await _disconnectDirect(connection.id);
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
      // Current [Config.resolveConnectionString] never yields empty; kept for
      // forward-compatible edge cases.
      // coverage:ignore-start
      return OdbcConnectionBuilder.build(overriddenDatabaseConfig);
      // coverage:ignore-end
    }

    if (resolved.isNotEmpty) {
      return resolved;
    }
    // coverage:ignore-start
    return OdbcConnectionBuilder.build(databaseConfig);
    // coverage:ignore-end
  }

  String _overrideDatabaseInConnectionString(
    String connectionString,
    String database,
  ) {
    var updated = connectionString;

    var replaced = false;
    for (final pattern in _connectionStringDatabasePatterns) {
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
    _metrics.recordConnectionPoolReleaseFailure();
    developer.log(
      'Failed to release pooled connection: $connectionId',
      name: 'database_gateway',
      level: 900,
      error: releaseError,
    );
  }

  ConnectionOptions _buildExpandedConnectionOptions(Object error) {
    final currentBufferBytes = OdbcConnectionOptionsBuilder.clampedMaxResultBufferMb(_settings) * 1024 * 1024;
    final expandedBufferBytes = OdbcGatewayBufferExpansion.calculateExpandedBufferBytes(
      currentBufferBytes: currentBufferBytes,
      errorMessage: _odbcErrorMessage(error),
    );
    final initialResultBufferBytes = expandedBufferBytes < ConnectionConstants.defaultInitialResultBufferBytes
        ? expandedBufferBytes
        : ConnectionConstants.defaultInitialResultBufferBytes;

    developer.log(
      'Expanding max result buffer for retry: '
      '$currentBufferBytes -> $expandedBufferBytes bytes',
      name: 'database_gateway',
      level: 800,
    );

    return ConnectionOptions(
      loginTimeout: Duration(
        seconds: OdbcConnectionOptionsBuilder.effectiveLoginTimeoutSeconds(
          _settings,
        ),
      ),
      queryTimeout: ConnectionConstants.defaultQueryTimeout,
      maxResultBufferBytes: expandedBufferBytes,
      initialResultBufferBytes: initialResultBufferBytes,
      autoReconnectOnConnectionLost: true,
      maxReconnectAttempts: ConnectionConstants.defaultMaxReconnectAttempts,
      reconnectBackoff: ConnectionConstants.defaultReconnectBackoff,
    );
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

  /// True when [request] asked for multi-result execution but the ODBC layer
  /// reported success with no materialized rows and no non-zero row-count
  /// items. Some pool/driver paths return an empty [QueryResultMulti] payload
  /// even though a direct connection returns data for the same SQL.
  bool _isVacuousMultiResultResponse(
    QueryRequest request,
    QueryResponse response,
  ) {
    if (!request.expectMultipleResults) {
      return false;
    }
    final hasRows = response.data.isNotEmpty || response.resultSets.any((QueryResultSet s) => s.rows.isNotEmpty);
    final hasNonZeroRowCount = response.items.any(
      (QueryResponseItem i) => i.isRowCount && (i.rowCount ?? 0) > 0,
    );
    return !hasRows && !hasNonZeroRowCount;
  }

  bool _queryFailureIndicatesInvalidConnectionId(domain.Failure failure) {
    final err = failure.context['error']?.toString() ?? failure.message;
    return _isInvalidConnectionIdError(err);
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

  DatabaseType _mapDriverNameToDatabaseType(String driverName) {
    return switch (driverName) {
      'SQL Server' => DatabaseType.sqlServer,
      'PostgreSQL' => DatabaseType.postgresql,
      'SQL Anywhere' => DatabaseType.sybaseAnywhere,
      _ => DatabaseType.sqlServer,
    };
  }

  Future<_QueryExecutionOutcome> _runQueryExecution(
    String connectionId,
    QueryRequest request,
    OdbcPreparedQueryExecution preparedExecution,
  ) async {
    if (OdbcGatewayQueryPreparation.shouldUseMultiResultExecution(
      request,
      preparedExecution,
    )) {
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

    final queryResult = preparedExecution.parameters != null && preparedExecution.parameters!.isNotEmpty
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
}
