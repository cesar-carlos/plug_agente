import 'dart:async';
import 'dart:io' as io;

import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_native_bulk_insert_pool.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/batch_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/bulk_insert_parallel_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_transaction_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_in_flight_execution_registry.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_native_bcp_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_native_bulk_insert_builder.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/connection_acquire_options_mapper.dart';
import 'package:result_dart/result_dart.dart';

/// Executes ODBC bulk inserts over a dedicated direct connection.
///
/// Extracted from `OdbcDatabaseGateway` so request validation, the native
/// `BulkInsertBuilder` mapping and the direct-connection lifecycle live behind
/// a focused, testable surface.
final class OdbcBulkInsertExecutor {
  OdbcBulkInsertExecutor({
    required OdbcGatewayConnectionManager connectionManager,
    required OdbcConnectionOptionsResolver optionsResolver,
    required OdbcService service,
    required MetricsCollector metrics,
    required IOdbcConnectionSettings settings,
    IOdbcNativeBulkInsertPool? parallelPool,
    OdbcInFlightExecutionRegistry? inFlightRegistry,
    OdbcStatementExecutor? statementExecutor,
  }) : _connectionManager = connectionManager,
       _optionsResolver = optionsResolver,
       _service = service,
       _metrics = metrics,
       _settings = settings,
       _parallelPool = parallelPool,
       _inFlightRegistry = inFlightRegistry,
       _statementExecutor =
           statementExecutor ??
           OdbcStatementExecutor(
             service: service,
             metrics: metrics,
             markConnectionForDiscard: connectionManager.markConnectionOutcomeUnknown,
           );

  final OdbcGatewayConnectionManager _connectionManager;
  final OdbcConnectionOptionsResolver _optionsResolver;
  final OdbcService _service;
  final MetricsCollector _metrics;
  final IOdbcConnectionSettings _settings;
  final IOdbcNativeBulkInsertPool? _parallelPool;
  final OdbcInFlightExecutionRegistry? _inFlightRegistry;
  final OdbcStatementExecutor _statementExecutor;

  /// Validates the shape of [request], returning a typed failure or null.
  static domain.Failure? validate(BulkInsertRequest request) {
    if (request.table.trim().isEmpty) {
      return domain.ValidationFailure('Bulk insert table is required');
    }
    if (request.columns.isEmpty) {
      return domain.ValidationFailure('Bulk insert requires at least one column');
    }
    if (request.rows.isEmpty) {
      return domain.ValidationFailure('Bulk insert requires at least one row');
    }
    for (final column in request.columns) {
      if (column.name.trim().isEmpty) {
        return domain.ValidationFailure('Bulk insert column names must not be empty');
      }
    }
    for (var i = 0; i < request.rows.length; i++) {
      if (request.rows[i].length != request.columns.length) {
        return domain.ValidationFailure.withContext(
          message: 'Bulk insert row length does not match column count',
          context: {
            'row_index': i,
            'row_length': request.rows[i].length,
            'column_count': request.columns.length,
          },
        );
      }
    }
    return null;
  }

  /// Runs [request] on an already acquired pooled or direct [connectionId].
  Future<Result<int>> executeOnConnection({
    required String connectionId,
    required BulkInsertRequest request,
    Duration? timeout,
    DateTime? deadline,
    DatabaseType? databaseType,
    CancellationToken? cancellationToken,
    String? sourceRpcRequestId,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return Failure(_cancelledFailure());
    }
    final inFlightRequestId = _inFlightTrackingKey(sourceRpcRequestId);
    final executionId = inFlightRequestId == null ? null : 'bulk:$connectionId';
    if (inFlightRequestId != null) {
      _inFlightRegistry?.register(
        inFlightRequestId,
        OdbcInFlightExecutionHandle(connectionId: connectionId),
        executionId: executionId,
      );
    }
    try {
      return await _executeChunkedBulkInsert(
        connectionId: connectionId,
        request: request,
        deadline: deadline ?? OdbcExecutionDeadline.deadlineFor(timeout),
        timeout: timeout,
        databaseType: databaseType,
        allowNativeBcp: false,
        cancellationToken: cancellationToken,
      );
    } finally {
      if (inFlightRequestId != null) {
        _inFlightRegistry?.unregister(
          inFlightRequestId,
          executionId: executionId,
        );
      }
    }
  }

  /// Runs the bulk insert on a freshly acquired direct connection, bounded by
  /// [timeout]. The connection is always disconnected and its lease released.
  ///
  /// When [databaseType] is SQL Server and the row count exceeds the parallel
  /// threshold, routes to `bulkInsertParallel` on the native pool instead.
  /// [requireAtomic] forces sequential bulk on one connection (with a local
  /// transaction for chunked inserts) and refuses parallel/BCP.
  Future<Result<int>> executeDirect(
    BulkInsertRequest request,
    String connectionString, {
    Duration? timeout,
    DatabaseType? databaseType,
    CancellationToken? cancellationToken,
    String? sourceRpcRequestId,
    bool requireAtomic = false,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Bulk insert execution cancelled',
          context: const {'cooperative_cancel': true},
        ),
      );
    }

    if (!_requiresWideTextBinding(request) &&
        databaseType != null &&
        BulkInsertParallelPolicy.shouldUseParallel(
          databaseType: databaseType,
          requestRowCount: request.rowCount,
          poolSize: _settings.poolSize,
          parallelPoolAvailable: _parallelPool != null,
          requireAtomic: requireAtomic,
        )) {
      return _executeParallelDirect(
        request,
        connectionString,
        timeout: timeout,
        parallelism: BulkInsertParallelPolicy.parallelismForPoolSize(_settings.poolSize),
        cancellationToken: cancellationToken,
      );
    }

    final deadline = OdbcExecutionDeadline.deadlineFor(timeout);
    final leaseResult = await _connectionManager.acquireDirectLease(
      operation: 'bulk_insert_direct',
      deadline: deadline,
    );
    if (leaseResult.isError()) {
      return Failure(leaseResult.exceptionOrNull()!);
    }
    final directLease = leaseResult.getOrThrow();
    var connectionEstablished = false;
    var directLeaseReleased = false;
    void releaseDirectLease() {
      if (directLeaseReleased) {
        return;
      }
      directLeaseReleased = true;
      directLease.release();
    }

    try {
      final connectResult = await _connectionManager.connectSafely(
        connectionString,
        options: _optionsResolver
            .forTimeout(
              OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout,
            )
            .toOdbcConnectionOptionsForConnectionString(connectionString),
      );
      return await connectResult.fold(
        (connection) async {
          connectionEstablished = true;
          final inFlightRequestId = _inFlightTrackingKey(sourceRpcRequestId);
          try {
            _registerInFlightExecution(inFlightRequestId, connection.id);
            final inserted = await _executeSequentialBulkInsert(
              connectionId: connection.id,
              request: request,
              deadline: deadline,
              timeout: timeout,
              databaseType: databaseType,
              wrapChunksInTransaction: true,
              forceTransaction: requireAtomic,
              allowNativeBcp: !requireAtomic,
              cancellationToken: cancellationToken,
            );
            if (inserted.isError()) {
              return Failure(inserted.exceptionOrNull()!);
            }
            return Success(inserted.getOrThrow());
          } on TimeoutException catch (error) {
            _connectionManager.markConnectionOutcomeUnknown(connection.id);
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'Bulk insert execution timeout',
                cause: error,
                context: {
                  'timeout': true,
                  'timeout_stage': 'sql',
                  'stage': 'bulk_insert',
                  'outcome_unknown': true,
                  'retryable': false,
                  'reason': RpcSqlBudgetConstants.queryTimeoutReason,
                  if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
                },
              ),
            );
          } finally {
            _unregisterInFlightExecution(inFlightRequestId);
            await _connectionManager.disconnectOwnedConnectionAndReleaseLease(
              connectionId: connection.id,
              directLease: directLease,
              operation: 'bulk_insert_direct_disconnect',
            );
          }
        },
        (error) {
          if (OdbcErrorInspector.isTimeout(error)) {
            _metrics.recordConnectTimeout();
          }
          return Failure(
            OdbcFailureMapper.mapConnectionError(
              error,
              operation: 'connect_direct',
            ),
          );
        },
      );
    } finally {
      if (!connectionEstablished) releaseDirectLease();
    }
  }

  Future<Result<int>> _executeParallelDirect(
    BulkInsertRequest request,
    String connectionString, {
    required int parallelism,
    Duration? timeout,
    CancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return Failure(_cancelledFailure());
    }
    final deadline = OdbcExecutionDeadline.deadlineFor(timeout);
    final poolIdResult = await _parallelPool!.ensurePoolId(connectionString);
    if (poolIdResult.isError()) {
      return Failure(poolIdResult.exceptionOrNull()!);
    }

    _metrics.recordBulkInsertParallel();
    return _executeChunkedBulkInsertParallel(
      poolId: poolIdResult.getOrThrow(),
      request: request,
      parallelism: parallelism,
      deadline: deadline,
      timeout: timeout,
      cancellationToken: cancellationToken,
    );
  }

  Future<Result<int>> _executeChunkedBulkInsertParallel({
    required int poolId,
    required BulkInsertRequest request,
    required int parallelism,
    required DateTime? deadline,
    required Duration? timeout,
    CancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return Failure(_cancelledFailure());
    }
    final chunkSize = ConnectionConstants.bulkInsertChunkRowCount;
    if (request.rows.length <= chunkSize) {
      return _executeSingleBulkInsertParallel(
        poolId: poolId,
        request: request,
        parallelism: parallelism,
        deadline: deadline,
        timeout: timeout,
        cancellationToken: cancellationToken,
      );
    }

    _metrics.recordBulkInsertChunked();
    var totalInserted = 0;
    for (var offset = 0; offset < request.rows.length; offset += chunkSize) {
      if (cancellationToken?.isCancelled ?? false) {
        return Failure(_cancelledFailure());
      }
      final end = offset + chunkSize < request.rows.length ? offset + chunkSize : request.rows.length;
      final chunkRequest = BulkInsertRequest(
        table: request.table,
        columns: request.columns,
        rows: request.rows.sublist(offset, end),
      );
      final chunkResult = await _executeSingleBulkInsertParallel(
        poolId: poolId,
        request: chunkRequest,
        parallelism: parallelism,
        deadline: deadline,
        timeout: timeout,
        cancellationToken: cancellationToken,
      );
      if (chunkResult.isError()) {
        return Failure(
          _parallelBulkFailure(
            chunkResult.exceptionOrNull()!,
            rowsInsertedBeforeFailure: totalInserted,
          ),
        );
      }
      totalInserted += chunkResult.getOrThrow();
    }
    return Success(totalInserted);
  }

  Future<Result<int>> _executeSingleBulkInsertParallel({
    required int poolId,
    required BulkInsertRequest request,
    required int parallelism,
    required DateTime? deadline,
    required Duration? timeout,
    CancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return Failure(_cancelledFailure());
    }
    final builder = _buildNativeBulkInsert(request);
    final operation = _service.bulkInsertParallel(
      poolId,
      builder.tableName,
      builder.columnNames,
      builder.build(),
      builder.rowCount,
      parallelism: parallelism,
    );
    final remaining = OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout;
    try {
      final result = remaining == null ? await operation : await operation.timeout(remaining);
      return await result.fold(
        Success.new,
        (error) => Failure(
          _parallelBulkFailure(
            OdbcFailureMapper.mapQueryError(
              error,
              operation: 'bulk_insert_parallel',
            ),
          ),
        ),
      );
    } on TimeoutException catch (error) {
      return Failure(
        _parallelBulkFailure(
          domain.QueryExecutionFailure.withContext(
            message: 'Bulk insert parallel execution timeout',
            cause: error,
            context: {
              'timeout': true,
              'timeout_stage': 'sql',
              'stage': 'bulk_insert_parallel',
              'reason': RpcSqlBudgetConstants.queryTimeoutReason,
              if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
            },
          ),
        ),
      );
    }
  }

  Future<Result<int>> _executeSequentialBulkInsert({
    required String connectionId,
    required BulkInsertRequest request,
    required DateTime? deadline,
    required Duration? timeout,
    required DatabaseType? databaseType,
    required bool wrapChunksInTransaction,
    required bool allowNativeBcp,
    bool forceTransaction = false,
    CancellationToken? cancellationToken,
  }) {
    final chunkSize = ConnectionConstants.bulkInsertChunkRowCount;
    final shouldWrap =
        wrapChunksInTransaction &&
        (forceTransaction || request.rows.length > chunkSize) &&
        !(allowNativeBcp && shouldAttemptNativeBcpBulkInsert(databaseType: databaseType));
    if (!shouldWrap) {
      return _executeChunkedBulkInsert(
        connectionId: connectionId,
        request: request,
        deadline: deadline,
        timeout: timeout,
        databaseType: databaseType,
        allowNativeBcp: allowNativeBcp,
        cancellationToken: cancellationToken,
      );
    }

    return _executeChunkedBulkInsertInTransaction(
      connectionId: connectionId,
      request: request,
      deadline: deadline,
      timeout: timeout,
      databaseType: databaseType,
      cancellationToken: cancellationToken,
    );
  }

  Future<Result<int>> _executeChunkedBulkInsertInTransaction({
    required String connectionId,
    required BulkInsertRequest request,
    required DateTime? deadline,
    required Duration? timeout,
    required DatabaseType? databaseType,
    CancellationToken? cancellationToken,
  }) async {
    final remaining = OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout;
    final manager = OdbcBatchTransactionManager(
      service: _service,
      metrics: _metrics,
      onRollbackUnconfirmed: _connectionManager.markConnectionOutcomeUnknown,
    );
    final beginResult = await manager.beginIfNeeded(
      connectionId: connectionId,
      transactionEnabled: true,
      accessMode: TransactionAccessMode.readWrite,
      lockTimeout: remaining,
      deadline: deadline,
    );
    if (beginResult.isError()) {
      if (OdbcErrorInspector.outcomeUnknown(beginResult.exceptionOrNull()!)) {
        _connectionManager.markConnectionOutcomeUnknown(connectionId);
      }
      return Failure(
        OdbcFailureMapper.mapQueryError(
          beginResult.exceptionOrNull()!,
          operation: 'bulk_insert_transaction_begin',
        ),
      );
    }

    final guard = BatchTransactionGuard(beginResult.getOrThrow().transactionId);
    Future<Result<int>> abort(Object error) async {
      if (OdbcErrorInspector.outcomeUnknown(error) || error is TimeoutException) {
        guard.markUnconfirmed();
        _connectionManager.markConnectionOutcomeUnknown(connectionId);
      }
      await guard.rollback((id) => manager.rollbackIfNeeded(connectionId, id));
      final mapped = OdbcFailureMapper.mapQueryError(
        error,
        operation: 'bulk_insert_transaction_execute',
        context: {
          if (guard.state == BatchTransactionState.unconfirmed) ...{
            'outcome_unknown': true,
            'retryable': false,
          },
          'rollback_confirmed': guard.rollbackConfirmed,
          if (guard.rollbackError != null)
            'secondary_errors': [
              OdbcFailureMapper.mapQueryError(guard.rollbackError!).context,
            ],
        },
      );
      return Failure(mapped);
    }

    try {
      final inserted = await _executeChunkedBulkInsert(
        connectionId: connectionId,
        request: request,
        deadline: deadline,
        timeout: timeout,
        databaseType: databaseType,
        allowNativeBcp: false,
        cancellationToken: cancellationToken,
      );
      if (inserted.isError()) return await abort(inserted.exceptionOrNull()!);
      final commit = await manager.commit(connectionId: connectionId, guard: guard, deadline: deadline);
      if (commit.isError()) return Failure(commit.exceptionOrNull()!);
      return inserted;
    } on Object catch (error) {
      return await abort(error);
    }
  }

  Future<Result<int>> _executeChunkedBulkInsert({
    required String connectionId,
    required BulkInsertRequest request,
    required DateTime? deadline,
    required Duration? timeout,
    DatabaseType? databaseType,
    bool allowNativeBcp = true,
    CancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return Failure(_cancelledFailure());
    }
    final chunkSize = ConnectionConstants.bulkInsertChunkRowCount;
    if (request.rows.length <= chunkSize) {
      return _executeSingleBulkInsert(
        connectionId: connectionId,
        request: request,
        deadline: deadline,
        timeout: timeout,
        databaseType: databaseType,
        allowNativeBcp: allowNativeBcp,
        cancellationToken: cancellationToken,
      );
    }

    _metrics.recordBulkInsertChunked();
    var totalInserted = 0;
    for (var offset = 0; offset < request.rows.length; offset += chunkSize) {
      if (cancellationToken?.isCancelled ?? false) {
        return Failure(_cancelledFailure());
      }
      final end = offset + chunkSize < request.rows.length ? offset + chunkSize : request.rows.length;
      final chunkRequest = BulkInsertRequest(
        table: request.table,
        columns: request.columns,
        rows: request.rows.sublist(offset, end),
      );
      final chunkResult = await _executeSingleBulkInsert(
        connectionId: connectionId,
        request: chunkRequest,
        deadline: deadline,
        timeout: timeout,
        databaseType: databaseType,
        allowNativeBcp: allowNativeBcp,
        cancellationToken: cancellationToken,
      );
      if (chunkResult.isError()) {
        return Failure(chunkResult.exceptionOrNull()!);
      }
      totalInserted += chunkResult.getOrThrow();
    }
    return Success(totalInserted);
  }

  Future<Result<int>> _executeSingleBulkInsert({
    required String connectionId,
    required BulkInsertRequest request,
    required DateTime? deadline,
    required Duration? timeout,
    DatabaseType? databaseType,
    bool allowNativeBcp = true,
    CancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return Failure(_cancelledFailure());
    }
    // Windows array binding in 5.0.0 uses narrow text buffers. Select the
    // public wide parameter path before dispatch so Unicode cannot be corrupted.
    if (_requiresWideTextBinding(request)) {
      return _executeWideTextChunk(
        connectionId: connectionId,
        request: request,
        deadline: deadline,
        timeout: timeout,
        cancellationToken: cancellationToken,
      );
    }
    final pilotEnabled = allowNativeBcp && shouldAttemptNativeBcpBulkInsert(databaseType: databaseType);
    if (pilotEnabled) {
      _metrics.recordDiagnosticReason(
        category: 'bulk_insert',
        reason: 'native_bcp_pilot',
      );
    }
    final builder = _buildNativeBulkInsert(request);
    final operation = _service.bulkInsert(
      connectionId,
      builder.tableName,
      builder.columnNames,
      builder.build(),
      builder.rowCount,
    );
    final remaining = OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout;
    final result = remaining == null ? await operation : await operation.timeout(remaining);
    return result.fold(
      Success.new,
      (error) {
        if (pilotEnabled && isNativeBcpUnsupportedError(error)) {
          return Failure(
            domain.QueryExecutionFailure.withContext(
              message: 'Native SQL Server BCP is disabled or unavailable',
              cause: error,
              context: const {
                'reason': odbcNativeBcpUnavailableReason,
                'requires_env': 'ODBC_ENABLE_UNSTABLE_NATIVE_BCP',
              },
            ),
          );
        }
        final mapped = OdbcFailureMapper.mapQueryError(
          error,
          operation: 'bulk_insert_direct',
        );
        if (pilotEnabled) {
          return Failure(
            domain.QueryExecutionFailure.withContext(
              message:
                  '${mapped.message} Native BCP may have committed some rows; '
                  'they were not rolled back as a single transaction.',
              cause: mapped.cause ?? error,
              context: {
                ...mapped.context,
                'reason': odbcNativeBcpFailedReason,
                'partial_writes': true,
                'user_message':
                    'A carga nativa BCP falhou. Parte das linhas pode já ter sido gravada. '
                    'Verifique a tabela antes de repetir a operação.',
              },
            ),
          );
        }
        return Failure(mapped);
      },
    );
  }

  bool _requiresWideTextBinding(BulkInsertRequest request) {
    if (!io.Platform.isWindows) return false;
    for (var column = 0; column < request.columns.length; column++) {
      if (request.columns[column].type != BulkInsertColumnType.text) continue;
      for (final row in request.rows) {
        final value = row[column];
        if (value != null && value.toString().codeUnits.any((unit) => unit > 127)) return true;
      }
    }
    return false;
  }

  Future<Result<int>> _executeWideTextChunk({
    required String connectionId,
    required BulkInsertRequest request,
    required DateTime? deadline,
    required Duration? timeout,
    CancellationToken? cancellationToken,
  }) async {
    final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    String quote(String path) {
      final parts = path.split('.');
      if (parts.any((part) => !identifier.hasMatch(part) || part.length > 128)) {
        throw const FormatException('Bulk insert requires a simple identifier path');
      }
      return parts.map((part) => '"$part"').join('.');
    }

    final statements = _statementExecutor;
    final owned = <String, int>{};
    Future<Result<int>> execute() async {
      final sql =
          'INSERT INTO ${quote(request.table)} '
          '(${request.columns.map((column) => quote(column.name)).join(', ')}) '
          'VALUES (${List.generate(request.columns.length, (index) => ':p$index').join(', ')})';
      final prepared = await statements.getOrPrepareStatement(
        connectionId: connectionId,
        preparedExecution: OdbcPreparedQueryExecution(
          sql: sql,
          parameters: {for (var index = 0; index < request.columns.length; index++) 'p$index': null},
        ),
        preparedStatements: owned,
        statementKey: sql,
        timeout: OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout,
      );
      if (prepared.isError()) return Failure(prepared.exceptionOrNull()!);
      _metrics.store.incrementEventCounter('odbc_bulk_wide_text_path');
      var inserted = 0;
      for (final row in request.rows) {
        if (cancellationToken?.isCancelled ?? false) return Failure(_cancelledFailure());
        final remaining = OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout;
        if (remaining != null && remaining <= Duration.zero) {
          return Failure(
            domain.QueryExecutionFailure.withContext(
              message: 'Bulk insert budget exhausted',
              context: const {'timeout': true, 'retryable': false, 'execution_not_started': true},
            ),
          );
        }
        final parameters = <String, Object?>{};
        for (var index = 0; index < row.length; index++) {
          final value = row[index];
          parameters['p$index'] = value == null
              ? null
              : switch (request.columns[index].type) {
                  BulkInsertColumnType.text => value.toString(),
                  BulkInsertColumnType.decimal => ParamValueDecimal(value.toString()),
                  BulkInsertColumnType.timestamp => value is DateTime ? value.toString() : value,
                  _ => value,
                };
        }
        final result = await statements.executePreparedStatementWithTimeout(
          connectionId: connectionId,
          preparedExecution: OdbcPreparedQueryExecution(sql: sql, parameters: parameters),
          statementId: prepared.getOrThrow(),
          timeout: remaining,
        );
        if (result.isError()) return Failure(result.exceptionOrNull()!);
        inserted++;
      }
      return Success(inserted);
    }

    Result<int> result;
    try {
      result = await execute();
    } on Object catch (error) {
      result = Failure(OdbcFailureMapper.mapQueryError(error, operation: 'bulk_insert_wide_text'));
    }
    final closed = await statements.closePreparedStatements(connectionId, owned.values);
    if (closed.isError()) {
      if (result.isSuccess()) return Failure(closed.exceptionOrNull()!);
      return Failure(
        OdbcFailureMapper.mapQueryError(
          result.exceptionOrNull()!,
          context: {
            'secondary_errors': [OdbcFailureMapper.mapQueryError(closed.exceptionOrNull()!).context],
          },
        ),
      );
    }
    return result;
  }

  domain.Failure _parallelBulkFailure(
    Object error, {
    int rowsInsertedBeforeFailure = 0,
  }) {
    final mapped = error is domain.Failure
        ? error
        : OdbcFailureMapper.mapQueryError(
            error,
            operation: 'bulk_insert_parallel',
          );
    return domain.QueryExecutionFailure.withContext(
      message:
          '${mapped.message} Parallel bulk insert is not atomic across connections; '
          'some rows may already have been committed and were not rolled back.',
      cause: mapped.cause ?? error,
      context: {
        ...mapped.context,
        'reason': OdbcContextConstants.bulkInsertPartialWritesReason,
        'partial_writes': true,
        'rows_inserted_before_failure': rowsInsertedBeforeFailure,
        'user_message':
            'A carga paralela falhou. Parte das linhas pode já ter sido gravada '
            'e não foi revertida em conjunto. Verifique a tabela antes de repetir a operação.',
      },
    );
  }

  domain.QueryExecutionFailure _cancelledFailure() {
    return domain.QueryExecutionFailure.withContext(
      message: 'Bulk insert execution cancelled',
      context: const <String, Object?>{'cooperative_cancel': true},
    );
  }

  BulkInsertBuilder _buildNativeBulkInsert(BulkInsertRequest request) {
    return OdbcNativeBulkInsertBuilder.fromRequest(request);
  }

  String? _inFlightTrackingKey(String? sourceRpcRequestId) {
    final normalized = sourceRpcRequestId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  void _registerInFlightExecution(String? requestId, String connectionId) {
    if (requestId == null || requestId.isEmpty) {
      return;
    }
    _inFlightRegistry?.register(
      requestId,
      OdbcInFlightExecutionHandle(connectionId: connectionId),
    );
  }

  void _unregisterInFlightExecution(String? requestId) {
    if (requestId == null || requestId.isEmpty) {
      return;
    }
    _inFlightRegistry?.unregister(requestId);
  }
}
