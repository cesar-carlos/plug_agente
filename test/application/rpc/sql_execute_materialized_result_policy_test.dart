import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_execute_materialized_result_policy.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';

void main() {
  group('SqlExecuteMaterializedResultPolicy', () {
    const policy = SqlExecuteMaterializedResultPolicy();
    const limits = TransportLimits();

    test('rejects materialized path when max rows exceed threshold and streaming is negotiated', () {
      final result = policy.rejectIfMaterializedPathUnsafe(
        effectiveMaxRows: ConnectionConstants.sqlExecuteMaterializedMaxRows,
        limits: limits,
        negotiatedExtensions: const {'streamingResults': true},
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.QueryExecutionFailure;
      expect(failure.context['reason'], RpcSqlBudgetConstants.materializedResultTooLargeReason);
      expect(failure.context['rpc_error_code'], RpcErrorCode.resultTooLarge);
      expect(failure.context['user_message'], isNotEmpty);
    });

    test('allows materialized path when streaming chunks are not negotiated', () {
      final result = policy.rejectIfMaterializedPathUnsafe(
        effectiveMaxRows: ConnectionConstants.sqlExecuteMaterializedMaxRows,
        limits: limits,
        negotiatedExtensions: const {'streamingResults': false},
      );

      expect(result.isSuccess(), isTrue);
    });

    test('allows materialized path when streamingResults is absent', () {
      final result = policy.rejectIfMaterializedPathUnsafe(
        effectiveMaxRows: ConnectionConstants.sqlExecuteMaterializedMaxRows,
        limits: limits,
        negotiatedExtensions: const {},
      );

      expect(result.isSuccess(), isTrue);
    });

    test('allows bounded materialized path below threshold', () {
      final result = policy.rejectIfMaterializedPathUnsafe(
        effectiveMaxRows: ConnectionConstants.sqlExecuteMaterializedMaxRows - 1,
        limits: limits,
        negotiatedExtensions: const {'streamingResults': true},
      );

      expect(result.isSuccess(), isTrue);
    });

    test('allows materialized ODBC fallback when streamingResults is absent', () {
      final result = policy.rejectIfMaterializedOdbcFallbackUnsafe(
        effectiveMaxRows: ConnectionConstants.sqlExecuteMaterializedMaxRows,
        limits: limits,
        negotiatedExtensions: const {},
        prefersDbStreaming: false,
      );

      expect(result.isSuccess(), isTrue);
    });

    test('rejects materialized ODBC fallback when streaming negotiated and max rows exceed threshold', () {
      final result = policy.rejectIfMaterializedOdbcFallbackUnsafe(
        effectiveMaxRows: ConnectionConstants.sqlExecuteMaterializedMaxRows,
        limits: limits,
        negotiatedExtensions: const {'streamingResults': true},
        prefersDbStreaming: true,
      );

      expect(result.isError(), isTrue);
    });

    test('rejects materialized streaming chunks when streaming negotiated and row count exceeds threshold', () {
      final result = policy.rejectIfMaterializedStreamingFallbackUnsafe(
        rowCount: limits.streamingRowThreshold + 1,
        limits: limits,
        negotiatedExtensions: const {'streamingResults': true},
        requestId: 'req-1',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.QueryExecutionFailure;
      expect(failure.context['reason'], RpcSqlBudgetConstants.materializedResultTooLargeReason);
      expect(failure.context['request_id'], 'req-1');
    });

    test('allows unpaginated playground materialized queries within materialized cap', () {
      final result = policy.rejectIfPlaygroundMaterializedUnsafe(
        trimmedQuery: 'SELECT * FROM Cliente',
        expectMultipleResults: false,
      );

      expect(result.isSuccess(), isTrue);
    });

    test('allows playground materialized queries with TOP row limit in SQL', () {
      final result = policy.rejectIfPlaygroundMaterializedUnsafe(
        trimmedQuery: 'SELECT TOP 100 * FROM large_table',
        expectMultipleResults: false,
      );

      expect(result.isSuccess(), isTrue);
    });

    test('allows playground materialized queries with FETCH/OFFSET in SQL', () {
      final result = policy.rejectIfPlaygroundMaterializedUnsafe(
        trimmedQuery: 'SELECT * FROM large_table ORDER BY id OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY',
        expectMultipleResults: false,
      );

      expect(result.isSuccess(), isTrue);
    });

    test('rejects paginated playground materialized query when page size exceeds cap', () {
      final result = policy.rejectIfPlaygroundMaterializedUnsafe(
        trimmedQuery: 'SELECT id FROM t ORDER BY id',
        expectMultipleResults: false,
        pageSize: ConnectionConstants.sqlExecuteMaterializedMaxRows + 1,
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.QueryExecutionFailure;
      expect(failure.context['reason'], RpcSqlBudgetConstants.materializedResultTooLargeReason);
      expect(failure.context['user_message'], isNotEmpty);
    });

    test('allows paginated playground materialized queries within page size', () {
      final result = policy.rejectIfPlaygroundMaterializedUnsafe(
        trimmedQuery: 'SELECT id FROM t ORDER BY id',
        expectMultipleResults: false,
        pageSize: 50,
      );

      expect(result.isSuccess(), isTrue);
    });
  });
}
