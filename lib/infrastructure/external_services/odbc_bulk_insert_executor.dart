import 'dart:async';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
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
  }) : _connectionManager = connectionManager,
       _optionsResolver = optionsResolver,
       _service = service,
       _metrics = metrics;

  final OdbcGatewayConnectionManager _connectionManager;
  final OdbcConnectionOptionsResolver _optionsResolver;
  final OdbcService _service;
  final MetricsCollector _metrics;

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

  /// Runs the bulk insert on a freshly acquired direct connection, bounded by
  /// [timeout]. The connection is always disconnected and its lease released.
  Future<Result<int>> executeDirect(
    BulkInsertRequest request,
    String connectionString, {
    Duration? timeout,
  }) async {
    final deadline = _deadlineFor(timeout);
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
        options: _optionsResolver.forTimeout(
          _remainingTimeoutFromDeadline(deadline) ?? timeout,
        ).toOdbcConnectionOptions(),
      );
      return await connectResult.fold(
        (connection) async {
          try {
            final builder = _buildNativeBulkInsert(request);
            final operation = _service.bulkInsert(
              connection.id,
              builder.tableName,
              builder.columnNames,
              builder.build(),
              builder.rowCount,
            );
            final remaining = _remainingTimeoutFromDeadline(deadline) ?? timeout;
            final result = remaining == null ? await operation : await operation.timeout(remaining);
            return result.fold(
              Success.new,
              (error) => Failure(
                OdbcFailureMapper.mapQueryError(
                  error,
                  operation: 'bulk_insert_direct',
                ),
              ),
            );
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

  BulkInsertBuilder _buildNativeBulkInsert(BulkInsertRequest request) {
    final builder = BulkInsertBuilder()..table(request.table);
    for (final column in request.columns) {
      builder.addColumn(
        column.name,
        _toNativeBulkColumnType(column.type),
        nullable: column.nullable,
        maxLen: column.maxLen,
      );
    }
    for (final row in request.rows) {
      builder.addRow(_coerceBulkInsertRow(row, request.columns));
    }
    return builder;
  }

  BulkColumnType _toNativeBulkColumnType(BulkInsertColumnType type) {
    return switch (type) {
      BulkInsertColumnType.i32 => BulkColumnType.i32,
      BulkInsertColumnType.i64 => BulkColumnType.i64,
      BulkInsertColumnType.text => BulkColumnType.text,
      BulkInsertColumnType.decimal => BulkColumnType.decimal,
      BulkInsertColumnType.binary => BulkColumnType.binary,
      BulkInsertColumnType.timestamp => BulkColumnType.timestamp,
    };
  }

  List<dynamic> _coerceBulkInsertRow(
    List<dynamic> row,
    List<BulkInsertColumn> columns,
  ) {
    return List<dynamic>.generate(row.length, (index) {
      final value = row[index];
      final column = columns[index];
      if (value == null || column.type != BulkInsertColumnType.timestamp) {
        return value;
      }
      if (value is BulkTimestamp) {
        return value;
      }
      if (value is DateTime) {
        return BulkTimestamp.fromDateTime(value);
      }
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          return BulkTimestamp.fromDateTime(parsed);
        }
      }
      return value;
    });
  }

  DateTime? _deadlineFor(Duration? timeout) {
    return timeout == null ? null : DateTime.now().add(timeout);
  }

  Duration? _remainingTimeoutFromDeadline(DateTime? deadline) {
    if (deadline == null) {
      return null;
    }
    final remaining = deadline.difference(DateTime.now());
    return remaining <= Duration.zero ? Duration.zero : remaining;
  }
}
