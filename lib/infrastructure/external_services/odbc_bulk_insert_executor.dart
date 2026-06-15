import 'dart:async';

import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_native_bulk_insert_pool.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/bulk_insert_parallel_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_native_bcp_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_native_bulk_insert_builder.dart';
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
  }) : _connectionManager = connectionManager,
       _optionsResolver = optionsResolver,
       _service = service,
       _metrics = metrics,
       _settings = settings,
       _parallelPool = parallelPool;

  final OdbcGatewayConnectionManager _connectionManager;
  final OdbcConnectionOptionsResolver _optionsResolver;
  final OdbcService _service;
  final MetricsCollector _metrics;
  final IOdbcConnectionSettings _settings;
  final IOdbcNativeBulkInsertPool? _parallelPool;

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
  }) {
    return _executeChunkedBulkInsert(
      connectionId: connectionId,
      request: request,
      deadline: deadline ?? OdbcExecutionDeadline.deadlineFor(timeout),
      timeout: timeout,
      databaseType: databaseType,
    );
  }

  /// Runs the bulk insert on a freshly acquired direct connection, bounded by
  /// [timeout]. The connection is always disconnected and its lease released.
  ///
  /// When [databaseType] is SQL Server and the row count exceeds the parallel
  /// threshold, routes to `bulkInsertParallel` on the native pool instead.
  Future<Result<int>> executeDirect(
    BulkInsertRequest request,
    String connectionString, {
    Duration? timeout,
    DatabaseType? databaseType,
  }) async {
    if (databaseType != null &&
        BulkInsertParallelPolicy.shouldUseParallel(
          databaseType: databaseType,
          requestRowCount: request.rowCount,
          poolSize: _settings.poolSize,
          parallelPoolAvailable: _parallelPool != null,
        )) {
      return _executeParallelDirect(
        request,
        connectionString,
        timeout: timeout,
        parallelism: BulkInsertParallelPolicy.parallelismForPoolSize(_settings.poolSize),
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
            .toOdbcConnectionOptions(),
      );
      return await connectResult.fold(
        (connection) async {
          try {
            final inserted = await _executeChunkedBulkInsert(
              connectionId: connection.id,
              request: request,
              deadline: deadline,
              timeout: timeout,
              databaseType: databaseType,
            );
            if (inserted.isError()) {
              return Failure(inserted.exceptionOrNull()!);
            }
            return Success(inserted.getOrThrow());
          } on TimeoutException catch (error) {
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'Bulk insert execution timeout',
                cause: error,
                context: {
                  'timeout': true,
                  'timeout_stage': 'sql',
                  'stage': 'bulk_insert',
                  'reason': RpcSqlBudgetConstants.queryTimeoutReason,
                  if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
                },
              ),
            );
          } finally {
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
      releaseDirectLease();
    }
  }

  Future<Result<int>> _executeParallelDirect(
    BulkInsertRequest request,
    String connectionString, {
    required int parallelism,
    Duration? timeout,
  }) async {
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
    );
  }

  Future<Result<int>> _executeChunkedBulkInsertParallel({
    required int poolId,
    required BulkInsertRequest request,
    required int parallelism,
    required DateTime? deadline,
    required Duration? timeout,
  }) async {
    final chunkSize = ConnectionConstants.bulkInsertChunkRowCount;
    if (request.rows.length <= chunkSize) {
      return _executeSingleBulkInsertParallel(
        poolId: poolId,
        request: request,
        parallelism: parallelism,
        deadline: deadline,
        timeout: timeout,
      );
    }

    _metrics.recordBulkInsertChunked();
    var totalInserted = 0;
    for (var offset = 0; offset < request.rows.length; offset += chunkSize) {
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
      );
      if (chunkResult.isError()) {
        return Failure(chunkResult.exceptionOrNull()!);
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
  }) async {
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
      return result.fold(
        Success.new,
        (error) => Failure(
          OdbcFailureMapper.mapQueryError(
            error,
            operation: 'bulk_insert_parallel',
          ),
        ),
      );
    } on TimeoutException catch (error) {
      return Failure(
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
      );
    }
  }

  Future<Result<int>> _executeChunkedBulkInsert({
    required String connectionId,
    required BulkInsertRequest request,
    required DateTime? deadline,
    required Duration? timeout,
    DatabaseType? databaseType,
  }) async {
    final chunkSize = ConnectionConstants.bulkInsertChunkRowCount;
    if (request.rows.length <= chunkSize) {
      return _executeSingleBulkInsert(
        connectionId: connectionId,
        request: request,
        deadline: deadline,
        timeout: timeout,
        databaseType: databaseType,
      );
    }

    _metrics.recordBulkInsertChunked();
    var totalInserted = 0;
    for (var offset = 0; offset < request.rows.length; offset += chunkSize) {
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
  }) async {
    final pilotEnabled = shouldAttemptNativeBcpBulkInsert(databaseType: databaseType);
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
              message: mapped.message,
              cause: mapped.cause ?? error,
              context: {
                ...mapped.context,
                'reason': odbcNativeBcpFailedReason,
              },
            ),
          );
        }
        return Failure(mapped);
      },
    );
  }

  BulkInsertBuilder _buildNativeBulkInsert(BulkInsertRequest request) {
    return OdbcNativeBulkInsertBuilder.fromRequest(request);
  }
}
