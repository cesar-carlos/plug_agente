import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/sql_rpc_handler_support.dart';
import 'package:plug_agente/application/rpc/sql_rpc_odbc_budget_runner.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';

class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

SqlRpcMethodHandlerSupport _support({
  Duration? Function({required DateTime? deadline, required Duration stageBudget})? effectiveStageTimeout,
}) {
  return SqlRpcMethodHandlerSupport(
    invalidParams: (_, detail, {rpcReason, extraFields = const {}}) => throw UnimplementedError(),
    methodNotFound: (_) => throw UnimplementedError(),
    executionNotFound: (_) => throw UnimplementedError(),
    consumeIdempotentCacheIfAny: (_, key, fingerprint) async => null,
    storeIdempotentSuccessIfApplicable:
        ({
          required request,
          required idempotencyKey,
          required idempotencyFingerprint,
          required response,
        }) async {},
    runIdempotentExecution:
        ({
          required request,
          required idempotencyKey,
          required idempotencyFingerprint,
          required execute,
          idempotentCachePrefetched = false,
        }) => execute(),
    buildMissingClientTokenFailure: () => domain.ConfigurationFailure('missing token'),
    authorizeWithBudget:
        ({
          required token,
          required sql,
          required requestDatabase,
          required requestId,
          required method,
          required deadline,
        }) async => const Success(unit),
    effectiveStageTimeout: effectiveStageTimeout ?? ({required deadline, required stageBudget}) => stageBudget,
  );
}

QueryRequest _queryRequest() {
  return QueryRequest(
    id: 'exec-1',
    agentId: 'agent-1',
    query: 'SELECT 1',
    timestamp: DateTime.utc(2024),
  );
}

BulkInsertRequest _bulkInsertRequest() {
  return const BulkInsertRequest(
    table: 'users',
    columns: [
      BulkInsertColumn(name: 'id', type: BulkInsertColumnType.i32),
    ],
    rows: [
      [1],
    ],
  );
}

QueryResponse _queryResponse() {
  return QueryResponse(
    id: 'exec-1',
    requestId: 'req-1',
    agentId: 'agent-1',
    data: const [],
    timestamp: DateTime.utc(2024),
  );
}

void main() {
  late MockDatabaseGateway mockGateway;

  setUpAll(() {
    registerFallbackValue(_queryRequest());
    registerFallbackValue(_bulkInsertRequest());
  });

  setUp(() {
    mockGateway = MockDatabaseGateway();
  });

  group('SqlRpcOdbcBudgetRunner.executeQuery', () {
    test('rejects materialized execute when negotiated streaming and max rows exceed threshold', () async {
      final runner = SqlRpcOdbcBudgetRunner(
        databaseGateway: mockGateway,
        support: _support(),
        queryStageBudget: const Duration(seconds: 30),
        batchExecutionStageBudget: const Duration(seconds: 35),
      );

      final result = await runner.executeQuery(
        _queryRequest(),
        database: null,
        requestId: 'req-large',
        deadline: DateTime.now().toUtc().add(const Duration(seconds: 30)),
        timeoutMs: 0,
        effectiveMaxRows: ConnectionConstants.sqlExecuteMaterializedMaxRows,
        transportLimits: const TransportLimits(),
        negotiatedExtensions: const {'streamingResults': true},
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.QueryExecutionFailure;
      expect(failure.context['reason'], RpcSqlBudgetConstants.materializedResultTooLargeReason);
      verifyNever(() => mockGateway.executeQuery(any()));
    });

    test('returns budget exhausted failure when stage timeout is zero', () async {
      final runner = SqlRpcOdbcBudgetRunner(
        databaseGateway: mockGateway,
        support: _support(
          effectiveStageTimeout: ({required deadline, required stageBudget}) => Duration.zero,
        ),
        queryStageBudget: const Duration(seconds: 30),
        batchExecutionStageBudget: const Duration(seconds: 35),
      );

      final result = await runner.executeQuery(
        _queryRequest(),
        database: null,
        requestId: 'req-1',
        deadline: DateTime.now().toUtc(),
        timeoutMs: 0,
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.QueryExecutionFailure;
      expect(failure.message, 'SQL execution budget exhausted before database call');
      expect(failure.context['stage'], 'query');
      expect(failure.context['reason'], RpcSqlBudgetConstants.queryBudgetExhaustedReason);
      expect(failure.context['request_id'], 'req-1');
      verifyNever(() => mockGateway.executeQuery(any()));
    });

    test('caps ODBC timeout with options.timeout_ms', () async {
      Duration? capturedTimeout;
      when(
        () => mockGateway.executeQuery(
          any(),
          timeout: any(named: 'timeout'),
          database: any(named: 'database'),
        ),
      ).thenAnswer((invocation) async {
        const sym = Symbol('timeout');
        capturedTimeout = invocation.namedArguments[sym] as Duration?;
        return Success(_queryResponse());
      });

      final runner = SqlRpcOdbcBudgetRunner(
        databaseGateway: mockGateway,
        support: _support(),
        queryStageBudget: const Duration(seconds: 30),
        batchExecutionStageBudget: const Duration(seconds: 35),
      );

      final result = await runner.executeQuery(
        _queryRequest(),
        database: 'erp_main',
        requestId: 'req-timeout',
        deadline: DateTime.now().toUtc().add(const Duration(seconds: 30)),
        timeoutMs: 8000,
      );

      expect(result.isSuccess(), isTrue);
      expect(capturedTimeout, isNotNull);
      expect(capturedTimeout!.inMilliseconds, lessThanOrEqualTo(8000));
    });

    test('calls gateway without timeout when stage budget is disabled', () async {
      when(() => mockGateway.executeQuery(any())).thenAnswer((_) async => Success(_queryResponse()));

      final runner = SqlRpcOdbcBudgetRunner(
        databaseGateway: mockGateway,
        support: _support(
          effectiveStageTimeout: ({required deadline, required stageBudget}) => null,
        ),
        queryStageBudget: const Duration(seconds: 30),
        batchExecutionStageBudget: const Duration(seconds: 35),
      );

      final result = await runner.executeQuery(
        _queryRequest(),
        database: null,
        requestId: null,
        deadline: null,
        timeoutMs: 0,
      );

      expect(result.isSuccess(), isTrue);
      verify(() => mockGateway.executeQuery(any())).called(1);
      verifyNever(
        () => mockGateway.executeQuery(
          any(),
          timeout: any(named: 'timeout'),
          database: any(named: 'database'),
        ),
      );
    });

    test('maps TimeoutException to query execution failure', () async {
      when(
        () => mockGateway.executeQuery(
          any(),
          timeout: any(named: 'timeout'),
          database: any(named: 'database'),
        ),
      ).thenThrow(TimeoutException('odbc timeout'));

      final runner = SqlRpcOdbcBudgetRunner(
        databaseGateway: mockGateway,
        support: _support(),
        queryStageBudget: const Duration(seconds: 30),
        batchExecutionStageBudget: const Duration(seconds: 35),
      );

      final result = await runner.executeQuery(
        _queryRequest(),
        database: 'erp_main',
        requestId: 'req-timeout',
        deadline: DateTime.now().toUtc().add(const Duration(seconds: 30)),
        timeoutMs: 0,
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.QueryExecutionFailure;
      expect(failure.message, 'SQL execution timeout');
      expect(failure.context['stage'], 'query');
      expect(failure.context['reason'], RpcSqlBudgetConstants.queryTimeoutReason);
      expect(failure.cause, isA<TimeoutException>());
    });
  });

  group('SqlRpcOdbcBudgetRunner.executeBulkInsert', () {
    test('returns budget exhausted failure when stage timeout is zero', () async {
      final runner = SqlRpcOdbcBudgetRunner(
        databaseGateway: mockGateway,
        support: _support(
          effectiveStageTimeout: ({required deadline, required stageBudget}) => Duration.zero,
        ),
        queryStageBudget: const Duration(seconds: 30),
        batchExecutionStageBudget: const Duration(seconds: 35),
      );

      final result = await runner.executeBulkInsert(
        _bulkInsertRequest(),
        database: 'erp_main',
        timeoutMs: 0,
        requestId: 'bulk-1',
        deadline: DateTime.now().toUtc(),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.QueryExecutionFailure;
      expect(failure.message, 'Bulk insert budget exhausted before database call');
      expect(failure.context['stage'], 'bulk_insert');
      expect(failure.context['reason'], RpcSqlBudgetConstants.bulkInsertBudgetExhaustedReason);
      verifyNever(
        () => mockGateway.executeBulkInsert(
          any(),
          database: any(named: 'database'),
          timeout: any(named: 'timeout'),
        ),
      );
    });

    test('caps ODBC timeout with options.timeout_ms', () async {
      Duration? capturedTimeout;
      when(
        () => mockGateway.executeBulkInsert(
          any(),
          database: any(named: 'database'),
          timeout: any(named: 'timeout'),
          sourceRpcRequestId: any(named: 'sourceRpcRequestId'),
        ),
      ).thenAnswer((invocation) async {
        const sym = Symbol('timeout');
        capturedTimeout = invocation.namedArguments[sym] as Duration?;
        return const Success(2);
      });

      final runner = SqlRpcOdbcBudgetRunner(
        databaseGateway: mockGateway,
        support: _support(),
        queryStageBudget: const Duration(seconds: 30),
        batchExecutionStageBudget: const Duration(seconds: 35),
      );

      final result = await runner.executeBulkInsert(
        _bulkInsertRequest(),
        database: 'erp_main',
        timeoutMs: 8000,
        requestId: 'bulk-1',
        deadline: DateTime.now().toUtc().add(const Duration(seconds: 35)),
      );

      expect(result.isSuccess(), isTrue);
      expect(capturedTimeout, isNotNull);
      expect(capturedTimeout!.inMilliseconds, lessThanOrEqualTo(8000));
    });

    test('maps TimeoutException to bulk insert execution failure', () async {
      when(
        () => mockGateway.executeBulkInsert(
          any(),
          database: any(named: 'database'),
          timeout: any(named: 'timeout'),
          sourceRpcRequestId: any(named: 'sourceRpcRequestId'),
        ),
      ).thenThrow(TimeoutException('odbc timeout'));

      final runner = SqlRpcOdbcBudgetRunner(
        databaseGateway: mockGateway,
        support: _support(),
        queryStageBudget: const Duration(seconds: 30),
        batchExecutionStageBudget: const Duration(seconds: 35),
      );

      final result = await runner.executeBulkInsert(
        _bulkInsertRequest(),
        database: 'erp_main',
        timeoutMs: 0,
        requestId: 'bulk-timeout',
        deadline: DateTime.now().toUtc().add(const Duration(seconds: 35)),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.QueryExecutionFailure;
      expect(failure.message, 'Bulk insert execution timeout');
      expect(failure.context['stage'], 'bulk_insert');
      expect(failure.context['reason'], RpcSqlBudgetConstants.queryTimeoutReason);
      expect(failure.cause, isA<TimeoutException>());
    });
  });
}
