import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/native_compatible_acquire_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/connection_acquire_options_mapper.dart';
import 'package:result_dart/result_dart.dart';

/// Pooled and direct ODBC query execution after config/retry resolution.
class OdbcQueryExecutionOrchestrator {
  OdbcQueryExecutionOrchestrator({
    required OdbcGatewayConnectionManager connectionManager,
    required OdbcQueryRunner queryRunner,
    required OdbcConnectionOptionsResolver optionsResolver,
    required NativeCompatibleAcquirePolicy nativeCompatiblePolicy,
    required MetricsCollector metrics,
    FeatureFlags? featureFlags,
    ISqlInvestigationCollector? sqlInvestigation,
  }) : _connectionManager = connectionManager,
       _queryRunner = queryRunner,
       _optionsResolver = optionsResolver,
       _nativeCompatiblePolicy = nativeCompatiblePolicy,
       _metrics = metrics,
       _featureFlags = featureFlags,
       _sqlInvestigation = sqlInvestigation;

  final OdbcGatewayConnectionManager _connectionManager;
  final OdbcQueryRunner _queryRunner;
  final OdbcConnectionOptionsResolver _optionsResolver;
  final NativeCompatibleAcquirePolicy _nativeCompatiblePolicy;
  final MetricsCollector _metrics;
  final FeatureFlags? _featureFlags;
  final ISqlInvestigationCollector? _sqlInvestigation;

  static const int _multiResultSqlLogPreviewChars = 120;
  static final RegExp _previewSqlWhitespaceCollapse = RegExp(r'\s+');

  static String _previewSqlForLog(String sql) {
    final collapsed = sql.replaceAll(_previewSqlWhitespaceCollapse, ' ').trim();
    if (collapsed.length <= _multiResultSqlLogPreviewChars) {
      return collapsed;
    }
    return '${collapsed.substring(0, _multiResultSqlLogPreviewChars)}…';
  }

  Future<Result<QueryResponse>> execute(
    QueryRequest request,
    String connectionString,
    DatabaseConfig databaseConfig, {
    Duration? timeout,
    CancellationToken? cancellationToken,
  }) async {
    final cancelled = _cooperativeCancelFailure(
      request: request,
      cancellationToken: cancellationToken,
    );
    if (cancelled != null) {
      return Failure(cancelled);
    }

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
      _recordSqlInvestigationExecutionFailure(
        request: request,
        preparedExecution: preparedExecution,
        errorMessage: queryValidation.message,
        executedInDb: false,
      );
      return Failure(queryValidation);
    }
    OdbcGatewayQueryPreparation.maybeLogPaginatedSqlRewrite(
      featureFlags: _featureFlags,
      request: request,
      databaseConfig: databaseConfig,
      preparedExecution: preparedExecution,
    );

    final baseOptions = _optionsResolver.forTimeout(timeout);
    final hintedOptions = _optionsResolver.hintedFor(
      connectionString: connectionString,
      sql: preparedExecution.sql,
      baseOptions: baseOptions,
    );
    if (hintedOptions != null) {
      developer.log(
        'Using cached adaptive buffer hint for pooled query execution',
        name: 'database_gateway',
        level: 800,
      );
      return _executeQueryWithPool(
        request,
        connectionString,
        stopwatch,
        preparedExecution: preparedExecution,
        timeout: timeout,
        acquireOptions: hintedOptions,
        cancellationToken: cancellationToken,
      );
    }

    return _executeQueryWithPool(
      request,
      connectionString,
      stopwatch,
      preparedExecution: preparedExecution,
      timeout: timeout,
      allowNativeCompatibleAcquire: _nativeCompatiblePolicy.shouldUseAcquire(
        databaseType: databaseConfig.databaseType,
        request: request,
        preparedExecution: preparedExecution,
        acquireOptions: null,
        timeout: timeout,
        defaultQueryTimeout: ConnectionConstants.defaultQueryTimeout,
        connectionString: connectionString,
      ),
      cancellationToken: cancellationToken,
    );
  }

  domain.QueryExecutionFailure? _cooperativeCancelFailure({
    required QueryRequest request,
    CancellationToken? cancellationToken,
  }) {
    if (cancellationToken?.isCancelled ?? false) {
      return domain.QueryExecutionFailure.withContext(
        message: 'SQL execution cancelled',
        context: {
          'query_id': request.id,
          'reason': OdbcContextConstants.executionCancelledReason,
          'cooperative_cancel': true,
        },
      );
    }
    return null;
  }

  Future<Result<QueryResponse>> _executeQueryWithPool(
    QueryRequest request,
    String connectionString,
    Stopwatch stopwatch, {
    required OdbcPreparedQueryExecution preparedExecution,
    required Duration? timeout,
    ConnectionAcquireOptions? acquireOptions,
    bool allowAdaptiveRetry = true,
    bool allowNativeCompatibleAcquire = false,
    DateTime? deadline,
    CancellationToken? cancellationToken,
  }) async {
    final effectiveDeadline = deadline ?? OdbcExecutionDeadline.deadlineFor(timeout);
    final poolAcquireOptions =
        acquireOptions ??
        _optionsResolver.forTimeout(
          OdbcExecutionDeadline.remainingFromDeadline(effectiveDeadline) ?? timeout,
        );
    final poolResult = allowNativeCompatibleAcquire
        ? await _connectionManager.acquireNativeCompatiblePooledConnection(
            connectionString,
            leaseFallbackOptions: poolAcquireOptions,
            deadline: effectiveDeadline,
            context: {'query_id': request.id},
          )
        : await _connectionManager.acquirePooledConnection(
            connectionString,
            options: poolAcquireOptions,
            deadline: effectiveDeadline,
            context: {'query_id': request.id},
          );

    if (poolResult.isError()) {
      stopwatch.stop();
      final error = poolResult.exceptionOrNull()!;
      final failure = error is domain.Failure
          ? error
          : OdbcFailureMapper.mapPoolError(
              error,
              operation: 'acquire_connection',
              context: {'query_id': request.id},
            );

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

      _recordSqlInvestigationExecutionFailure(
        request: request,
        preparedExecution: preparedExecution,
        errorMessage: _odbcErrorMessage(error),
        executedInDb: false,
      );

      return Failure(
        failure,
      );
    }

    final cancelledAfterAcquire = _cooperativeCancelFailure(
      request: request,
      cancellationToken: cancellationToken,
    );
    if (cancelledAfterAcquire != null) {
      stopwatch.stop();
      await _connectionManager.releaseConnectionSafely(poolResult.getOrThrow());
      return Failure(cancelledAfterAcquire);
    }

    final connId = poolResult.getOrThrow();
    var releasedConnectionEarly = false;
    final effectiveOptions = poolAcquireOptions;

    try {
      final outcome = await _queryRunner.runWithTimeout(
        connId: connId,
        request: request,
        preparedExecution: preparedExecution,
        connectionString: connectionString,
        timeout: OdbcExecutionDeadline.remainingFromDeadline(effectiveDeadline) ?? timeout,
        executionMode: allowNativeCompatibleAcquire ? 'native_compatible' : 'pooled',
        cancellationToken: cancellationToken,
      );

      if (outcome.isSuccess && allowNativeCompatibleAcquire && timeout != null && timeout > Duration.zero) {
        _nativeCompatiblePolicy.rememberNativeCompatibleTimeout(
          connectionString: connectionString,
          timeout: timeout,
        );
      }

      if (!outcome.isSuccess) {
        final error = outcome.error!;
        if (_isInvalidConnectionIdError(error)) {
          _connectionManager.recordPooledExecutionFailure(
            connectionString: connectionString,
            connectionId: connId,
            error: error,
            stage: 'query',
          );
          _connectionManager.markConnectionForDiscard(connId);
          await _connectionManager.releaseConnectionSafely(connId);
          releasedConnectionEarly = true;
          await _connectionManager.tryRecoverPoolAfterInvalidConnectionId(connectionString);
          _metrics.recordOdbcInvalidConnectionRecycle();
          _metrics.recordDirectConnectionFallback();
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
            cancellationToken: cancellationToken,
          );
        }

        if (allowAdaptiveRetry && _optionsResolver.isBufferTooSmallError(error)) {
          _metrics.recordOdbcBufferExpansion();
          _metrics.recordDiagnosticReason(
            category: 'query',
            reason: OdbcContextConstants.bufferTooSmallReason,
          );
          _connectionManager.recordPooledExecutionFailure(
            connectionString: connectionString,
            connectionId: connId,
            error: error,
            stage: 'query',
          );
          final currentBufferBytes =
              effectiveOptions.maxResultBufferBytes ?? ConnectionConstants.defaultMaxResultBufferBytes;
          _optionsResolver.rememberExpandedBuffer(
            connectionString: connectionString,
            sql: preparedExecution.sql,
            currentBufferBytes: currentBufferBytes,
            error: error,
          );
          developer.log(
            'Buffer too small in pooled query, retrying with expanded buffer',
            name: 'database_gateway',
            level: 900,
            error: error,
          );
          await _connectionManager.releaseConnectionSafely(connId);
          releasedConnectionEarly = true;
          return _executeQueryWithPool(
            request,
            connectionString,
            stopwatch,
            preparedExecution: preparedExecution,
            timeout: timeout,
            acquireOptions: _optionsResolver.expandedFor(
              error,
              baseOptions: effectiveOptions,
              currentBufferBytes: currentBufferBytes,
            ),
            allowAdaptiveRetry: false,
            deadline: effectiveDeadline,
            cancellationToken: cancellationToken,
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

        _recordSqlInvestigationExecutionFailure(
          request: request,
          preparedExecution: preparedExecution,
          errorMessage: msg,
          executedInDb: true,
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
        _metrics.recordDirectConnectionFallback();
        await _connectionManager.releaseConnectionSafely(connId);
        releasedConnectionEarly = true;
        return _executeQueryWithoutPool(
          request,
          connectionString,
          stopwatch,
          preparedExecution: preparedExecution,
          timeout: timeout,
          afterVacuousPooledMulti: true,
          deadline: effectiveDeadline,
          cancellationToken: cancellationToken,
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
    } on CancellationException catch (error) {
      stopwatch.stop();
      _metrics.recordFailure(
        queryId: request.id,
        query: request.query,
        executionDuration: stopwatch.elapsed,
        errorMessage: 'SQL execution cancelled',
      );
      _recordSqlInvestigationExecutionFailure(
        request: request,
        preparedExecution: preparedExecution,
        errorMessage: 'SQL execution cancelled',
        executedInDb: false,
      );
      return Failure(
        OdbcFailureMapper.mapQueryError(
          error,
          operation: 'execute_query',
          context: {'query_id': request.id, 'cooperative_cancel': true},
        ),
      );
    } on TimeoutException catch (error) {
      stopwatch.stop();
      _metrics.recordFailure(
        queryId: request.id,
        query: request.query,
        executionDuration: stopwatch.elapsed,
        errorMessage: 'Query execution timeout',
      );
      _recordSqlInvestigationExecutionFailure(
        request: request,
        preparedExecution: preparedExecution,
        errorMessage: 'Query execution timeout',
        executedInDb: true,
      );
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'SQL execution timeout',
          cause: error,
          context: {
            'timeout': true,
            'timeout_stage': 'sql',
            'stage': 'query',
            'reason': RpcSqlBudgetConstants.queryTimeoutReason,
            if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
          },
        ),
      );
    } finally {
      if (!releasedConnectionEarly) {
        await _connectionManager.releaseConnectionSafely(connId);
      }
    }
  }

  Future<Result<QueryResponse>> _executeQueryWithoutPool(
    QueryRequest request,
    String connectionString,
    Stopwatch stopwatch, {
    required OdbcPreparedQueryExecution preparedExecution,
    ConnectionAcquireOptions? options,
    Duration? timeout,
    bool afterVacuousPooledMulti = false,
    bool allowAdaptiveRetry = true,
    DateTime? deadline,
    CancellationToken? cancellationToken,
  }) async {
    final cancelled = _cooperativeCancelFailure(
      request: request,
      cancellationToken: cancellationToken,
    );
    if (cancelled != null) {
      stopwatch.stop();
      return Failure(cancelled);
    }

    final effectiveDeadline = deadline ?? OdbcExecutionDeadline.deadlineFor(timeout);
    final leaseResult = await _connectionManager.acquireDirectLease(
      operation: 'query_direct',
      deadline: effectiveDeadline,
    );
    if (leaseResult.isError()) {
      stopwatch.stop();
      final leaseFailure = leaseResult.exceptionOrNull()!;
      _recordSqlInvestigationExecutionFailure(
        request: request,
        preparedExecution: preparedExecution,
        errorMessage: leaseFailure.toString(),
        executedInDb: false,
      );
      return Failure(leaseFailure);
    }
    final directLease = leaseResult.getOrThrow();
    final cancelledAfterLease = _cooperativeCancelFailure(
      request: request,
      cancellationToken: cancellationToken,
    );
    if (cancelledAfterLease != null) {
      stopwatch.stop();
      directLease.release();
      return Failure(cancelledAfterLease);
    }
    var directLeaseReleased = false;
    void releaseDirectLease() {
      if (directLeaseReleased) {
        return;
      }
      directLeaseReleased = true;
      directLease.release();
    }

    final effectiveOptions =
        options ??
        _optionsResolver.forTimeout(
          OdbcExecutionDeadline.remainingFromDeadline(effectiveDeadline) ?? timeout,
        );

    try {
      final connectResult = await _connectionManager.connectSafely(
        connectionString,
        options: effectiveOptions.toOdbcConnectionOptions(),
      );
      return await connectResult.fold(
        (connection) async {
          var connectionCleanedUp = false;

          Future<void> cleanupOwnedConnection() async {
            if (connectionCleanedUp) {
              return;
            }
            connectionCleanedUp = true;
            await _connectionManager.disconnectOwnedConnectionAndReleaseLease(
              connectionId: connection.id,
              directLease: directLease,
              operation: 'query_direct_disconnect',
            );
          }

          try {
            final outcome = await _queryRunner.runWithTimeout(
              connId: connection.id,
              request: request,
              preparedExecution: preparedExecution,
              connectionString: connectionString,
              timeout: OdbcExecutionDeadline.remainingFromDeadline(effectiveDeadline) ?? timeout,
              executionMode: 'direct',
              cancellationToken: cancellationToken,
            );
            if (!outcome.isSuccess) {
              final error = outcome.error!;
              if (_optionsResolver.isBufferTooSmallError(error)) {
                _metrics.recordOdbcBufferExpansion();
                _metrics.recordDiagnosticReason(
                  category: 'query',
                  reason: OdbcContextConstants.bufferTooSmallReason,
                );
                final currentBufferBytes =
                    effectiveOptions.maxResultBufferBytes ?? ConnectionConstants.defaultMaxResultBufferBytes;
                _optionsResolver.rememberExpandedBuffer(
                  connectionString: connectionString,
                  sql: preparedExecution.sql,
                  currentBufferBytes: currentBufferBytes,
                  error: error,
                );

                if (allowAdaptiveRetry) {
                  await cleanupOwnedConnection();
                  developer.log(
                    'Buffer too small in direct query, retrying with expanded buffer',
                    name: 'database_gateway',
                    level: 900,
                    error: error,
                  );
                  return _executeQueryWithoutPool(
                    request,
                    connectionString,
                    stopwatch,
                    preparedExecution: preparedExecution,
                    options: _optionsResolver.expandedFor(
                      error,
                      baseOptions: effectiveOptions,
                      currentBufferBytes: currentBufferBytes,
                    ),
                    timeout: timeout,
                    afterVacuousPooledMulti: afterVacuousPooledMulti,
                    allowAdaptiveRetry: false,
                    deadline: effectiveDeadline,
                    cancellationToken: cancellationToken,
                  );
                }
              }
              stopwatch.stop();
              _metrics.recordFailure(
                queryId: request.id,
                query: request.query,
                executionDuration: stopwatch.elapsed,
                errorMessage: _odbcErrorMessage(error),
              );
              _recordSqlInvestigationExecutionFailure(
                request: request,
                preparedExecution: preparedExecution,
                errorMessage: _odbcErrorMessage(error),
                executedInDb: true,
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
          } on CancellationException catch (error) {
            stopwatch.stop();
            _metrics.recordFailure(
              queryId: request.id,
              query: request.query,
              executionDuration: stopwatch.elapsed,
              errorMessage: 'SQL execution cancelled',
            );
            _recordSqlInvestigationExecutionFailure(
              request: request,
              preparedExecution: preparedExecution,
              errorMessage: 'SQL execution cancelled',
              executedInDb: false,
            );
            return Failure(
              OdbcFailureMapper.mapQueryError(
                error,
                operation: 'execute_query_direct',
                context: {'query_id': request.id, 'cooperative_cancel': true},
              ),
            );
          } on TimeoutException catch (error) {
            stopwatch.stop();
            _metrics.recordFailure(
              queryId: request.id,
              query: request.query,
              executionDuration: stopwatch.elapsed,
              errorMessage: 'Query execution timeout',
            );
            _recordSqlInvestigationExecutionFailure(
              request: request,
              preparedExecution: preparedExecution,
              errorMessage: 'Query execution timeout',
              executedInDb: true,
            );
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'SQL execution timeout',
                cause: error,
                context: {
                  'timeout': true,
                  'timeout_stage': 'sql',
                  'stage': 'query',
                  'reason': RpcSqlBudgetConstants.queryTimeoutReason,
                  if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
                },
              ),
            );
          } finally {
            await cleanupOwnedConnection();
          }
        },
        (error) {
          if (_looksLikeTimeoutError(error)) {
            _metrics.recordConnectTimeout();
          }
          stopwatch.stop();
          _metrics.recordFailure(
            queryId: request.id,
            query: request.query,
            executionDuration: stopwatch.elapsed,
            errorMessage: _odbcErrorMessage(error),
          );
          _recordSqlInvestigationExecutionFailure(
            request: request,
            preparedExecution: preparedExecution,
            errorMessage: _odbcErrorMessage(error),
            executedInDb: false,
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
    } finally {
      releaseDirectLease();
    }
  }

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

  bool _isInvalidConnectionIdError(Object error) => OdbcErrorInspector.isInvalidConnectionId(error);

  bool _looksLikeTimeoutError(Object error) => OdbcErrorInspector.isTimeout(error);

  String _odbcErrorMessage(Object error) => OdbcErrorInspector.message(error);

  void _recordSqlInvestigationExecutionFailure({
    required QueryRequest request,
    required OdbcPreparedQueryExecution preparedExecution,
    required String errorMessage,
    required bool executedInDb,
    String method = 'sql.execute',
  }) {
    if (!(_featureFlags?.enableDashboardSqlInvestigationFeed ?? true)) {
      return;
    }
    final inv = _sqlInvestigation;
    if (inv == null) {
      return;
    }
    final original = request.query;
    final effective = preparedExecution.sql;
    final effectiveForUi = original.trim() == effective.trim() ? null : effective;
    inv.recordExecutionFailure(
      method: method,
      originalSql: original,
      errorMessage: errorMessage,
      executedInDb: executedInDb,
      effectiveSql: effectiveForUi,
      rpcRequestId: request.sourceRpcRequestId,
      internalQueryId: request.id,
    );
  }
}
