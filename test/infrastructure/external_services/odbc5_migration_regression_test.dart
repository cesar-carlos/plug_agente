import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/batch_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_transaction_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_prepared_statement_cache_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_result_encoding_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/odbc_native_connection_pool.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class _Service extends Mock implements OdbcService {}

class _Convertible implements Exception, OdbcErrorConvertible {
  const _Convertible(this.error);
  final OdbcError error;
  @override
  String get message => error.message;
  @override
  OdbcError toOdbcError() => error;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const StatementOptions());
    registerFallbackValue(const PoolOptions());
    registerFallbackValue(const ConnectionOptions());
  });
  late _Service service;
  late MetricsCollector metrics;
  late OdbcStatementExecutor statements;
  late List<String> discarded;
  setUp(() {
    service = _Service();
    metrics = MetricsCollector();
    discarded = [];
    statements = OdbcStatementExecutor(service: service, metrics: metrics, markConnectionForDiscard: discarded.add);
  });
  tearDown(() => metrics.dispose());

  const uncertain = QueryError(
    message: 'Deadline exceeded',
    details: OdbcErrorDetails(
      code: OdbcErrorCode.timeout,
      operation: 'commitTransaction',
      connectionId: '7',
      transactionId: '9',
      requestId: 12,
      workerId: 2,
      attempt: 1,
      outcomeUnknown: true,
      secondaryErrors: [
        QueryError(
          message: 'cleanup secret',
          details: OdbcErrorDetails(code: OdbcErrorCode.cleanup),
        ),
      ],
    ),
  );
  const sample = QueryResult(
    columns: ['v'],
    rows: [
      [1],
    ],
    rowCount: 1,
  );

  test('preserves structured timeout and uncertainty despite caller context overrides', () {
    final failure = OdbcFailureMapper.mapQueryError(
      const _Convertible(uncertain),
      context: const {'outcome_unknown': false, 'retryable': true},
    );
    expect(failure.context['timeout'], isTrue);
    expect(failure.context['outcome_unknown'], isTrue);
    expect(failure.context['retryable'], isFalse);
    expect(failure.context['odbc_request_id'], 12);
    expect(failure.context['odbc_worker_id'], 2);
    expect(failure.context['odbc_transaction_id'], '9');
    expect(failure.context['secondary_errors'], hasLength(1));
    expect(failure.cause, isA<_Convertible>());
  });

  test('explicit error code takes precedence over timeout wording', () {
    const error = QueryError(
      message: 'timeout table does not exist',
      details: OdbcErrorDetails(code: OdbcErrorCode.query),
    );
    expect(OdbcErrorInspector.isTimeout(error), isFalse);
    expect(OdbcFailureMapper.mapQueryError(error).context['timeout'], isNot(true));
  });

  test('nested uncertainty blocks RPC retry and does not expose technical stack traces', () {
    final failure = domain.QueryExecutionFailure.withContext(
      message: 'Unknown result',
      cause: uncertain,
      context: const {
        'outcome_unknown': true,
        'retryable': true,
        'odbc_stack_trace': 'private stack',
        'odbc_error_code': 'query',
        'error': 'private SQL parameter value',
      },
    );
    final rpc = FailureToRpcErrorMapper.map(failure);
    expect((rpc.data! as Map<String, dynamic>)['retryable'], isFalse);
    expect(rpc.data.toString(), isNot(contains('private stack')));
    expect(rpc.data.toString(), isNot(contains('private SQL parameter value')));
  });

  test('uncertain commit never rolls back in subsequent cleanup', () async {
    when(() => service.commitTransaction('7', 9)).thenAnswer((_) async => const Failure(uncertain));
    final guard = BatchTransactionGuard(9);
    final manager = OdbcBatchTransactionManager(
      service: service,
      metrics: metrics,
      onRollbackUnconfirmed: discarded.add,
    );
    final committed = await manager.commit(connectionId: '7', guard: guard);
    await guard.rollback((id) => manager.rollbackIfNeeded('7', id));
    expect(committed.isError(), isTrue);
    expect(guard.state, BatchTransactionState.unconfirmed);
    expect(discarded, ['7']);
    verifyNever(() => service.rollbackTransaction(any(), any()));
    await manager.commit(connectionId: '7', guard: guard);
    verify(() => service.commitTransaction('7', 9)).called(1);
  });

  test('failed rollback remains unconfirmed and is not attempted twice', () async {
    final guard = BatchTransactionGuard(9);
    var calls = 0;
    Future<Result<void>> rollback(int id) async {
      calls++;
      return const Failure(uncertain);
    }

    await guard.rollback(rollback);
    await guard.rollback(rollback);
    expect(guard.rollbackConfirmed, isFalse);
    expect(guard.state, BatchTransactionState.unconfirmed);
    expect(calls, 1);
  });

  test('native policy closes every explicitly prepared one-shot statement', () async {
    when(
      () => service.prepareNamed('7', 'SELECT @v', timeoutMs: any(named: 'timeoutMs')),
    ).thenAnswer((_) async => const Success(10));
    when(() => service.executePreparedNamed('7', 10, any(), any())).thenAnswer((_) async => const Success(sample));
    when(() => service.closeStatement('7', 10)).thenAnswer((_) async => const Success(unit));
    final runner = OdbcQueryRunner(
      queries: service,
      metrics: metrics,
      statementExecutor: statements,
      resultEncodingExecutor: OdbcResultEncodingExecutor(service),
      markConnectionForDiscard: discarded.add,
    );
    final outcome = await runner.runPrepared(
      connectionId: '7',
      request: QueryRequest(id: 'r', agentId: 'a', query: 'SELECT @v', timestamp: DateTime.now()),
      preparedExecution: const OdbcPreparedQueryExecution(sql: 'SELECT @v', parameters: {'v': 1}),
      cachePolicy: OdbcPreparedStatementCachePolicy.nativePool,
    );
    expect(outcome.isSuccess, isTrue);
    verify(() => service.closeStatement('7', 10)).called(1);
  });

  test('one-shot cleanup failure becomes an explicit failure', () async {
    when(
      () => service.prepare('7', 'SELECT 1', timeoutMs: any(named: 'timeoutMs')),
    ).thenAnswer((_) async => const Success(10));
    when(
      () => service.executePreparedParamValues('7', 10, any(), any()),
    ).thenAnswer((_) async => const Success(sample));
    when(
      () => service.closeStatement('7', 10),
    ).thenAnswer((_) async => const Failure(QueryError(message: 'close failed')));
    final runner = OdbcQueryRunner(
      queries: service,
      metrics: metrics,
      statementExecutor: statements,
      resultEncodingExecutor: OdbcResultEncodingExecutor(service),
      markConnectionForDiscard: discarded.add,
    );
    final outcome = await runner.runPrepared(
      connectionId: '7',
      request: QueryRequest(id: 'r', agentId: 'a', query: 'SELECT 1', timestamp: DateTime.now()),
      preparedExecution: const OdbcPreparedQueryExecution(sql: 'SELECT 1', parameters: null),
    );
    expect(outcome.isSuccess, isFalse);
    expect(discarded, contains('7'));
  });

  test('timeout defers statement close until execution actually completes', () async {
    final work = Completer<Result<QueryResult>>();
    when(() => service.executePreparedParamValues('7', 10, any(), any())).thenAnswer((_) => work.future);
    when(
      () => service.cancelStatement('7', 10),
    ).thenAnswer((_) async => const Failure(UnsupportedFeatureError(message: 'unsupported')));
    when(() => service.closeStatement('7', 10)).thenAnswer((_) async => const Success(unit));
    await expectLater(
      statements.executePreparedStatementWithTimeout(
        connectionId: '7',
        statementId: 10,
        preparedExecution: const OdbcPreparedQueryExecution(sql: 'SELECT 1', parameters: null),
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<QueryError>().having((error) => error.details.outcomeUnknown, 'uncertainty', true)),
    );
    await statements.closePreparedStatements('7', [10]);
    verifyNever(() => service.closeStatement('7', 10));
    work.complete(const Success(sample));
    await Future<void>.delayed(Duration.zero);
    verify(() => service.closeStatement('7', 10)).called(1);
    expect(metrics.timeoutCancelSuccessCount, 0);
  });

  Future<OdbcNativeConnectionPool> acquiredPool() async {
    when(
      () => service.poolCreate(
        any(),
        any(),
        options: any(named: 'options'),
        connectionOptions: any(named: 'connectionOptions'),
      ),
    ).thenAnswer((_) async => const Success(1));
    when(() => service.poolGetConnection(1)).thenAnswer(
      (_) async =>
          Success(Connection(id: '7', connectionString: 'DSN=test', createdAt: DateTime.now(), isActive: true)),
    );
    final pool = OdbcNativeConnectionPool(service, MockOdbcConnectionSettings(), metricsCollector: metrics);
    await pool.acquire('DSN=test');
    return pool;
  }

  test('concurrent release sends one checkin and decrements ownership once', () async {
    final pool = await acquiredPool();
    final release = Completer<Result<void>>();
    when(() => service.poolReleaseConnection('7')).thenAnswer((_) => release.future);
    final first = pool.release('7');
    final second = pool.release('7');
    release.complete(const Success(unit));
    await Future.wait([first, second]);
    await pool.release('7');
    verify(() => service.poolReleaseConnection('7')).called(1);
    expect(pool.getHealthDiagnostics()['native_active_count'], 0);
  });

  test('unknown completion retains capacity and blocks checkout without checkin', () async {
    final pool = await acquiredPool();
    final discardedResult = await pool.discard('7', reason: PoolDiscardReason.outcomeUnknown);
    expect(discardedResult.isError(), isTrue);
    expect(pool.getHealthDiagnostics()['native_active_count'], 1);
    expect(pool.getHealthDiagnostics()['native_unconfirmed_connection_count'], 1);
    expect((await pool.acquire('DSN=test')).isError(), isTrue);
    verifyNever(() => service.poolReleaseConnection(any()));
  });

  test('expired transaction budget does not dispatch begin or commit', () async {
    final manager = OdbcBatchTransactionManager(service: service, metrics: metrics);
    final deadline = DateTime.now().subtract(const Duration(seconds: 1));
    final start = await manager.beginIfNeeded(
      connectionId: '7',
      transactionEnabled: true,
      lockTimeout: null,
      accessMode: TransactionAccessMode.readWrite,
      deadline: deadline,
    );
    expect(start.isError(), isTrue);
    final guard = BatchTransactionGuard(9);
    expect((await manager.commit(connectionId: '7', guard: guard, deadline: deadline)).isError(), isTrue);
    expect(guard.state, BatchTransactionState.active);
    verifyNever(() => service.commitTransaction(any(), any()));
  });

  test('late statement completion cannot close a handle after runtime invalidation', () async {
    final pending = Completer<Result<QueryResult>>();
    when(() => service.executePreparedNamed('7', 10, any(), any())).thenAnswer((_) => pending.future);
    final execution = statements.executePreparedStatementWithTimeout(
      connectionId: '7',
      statementId: 10,
      preparedExecution: const OdbcPreparedQueryExecution(sql: 'SELECT :v', parameters: {'v': 1}),
    );
    await statements.closePreparedStatements('7', [10]);
    statements.invalidateAfterWorkerRecovery();
    pending.complete(const Success(sample));
    expect((await execution).isError(), isTrue);
    verifyNever(() => service.closeStatement('7', 10));
  });
}
