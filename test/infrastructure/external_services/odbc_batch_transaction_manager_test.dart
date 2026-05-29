import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/batch_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_transaction_manager.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

class _MockOdbcService extends Mock implements OdbcService {}

void main() {
  setUpAll(() {
    registerFallbackValue(SavepointDialect.auto);
    registerFallbackValue(TransactionAccessMode.readWrite);
  });

  late _MockOdbcService service;
  late MetricsCollector metrics;
  late OdbcBatchTransactionManager manager;

  setUp(() {
    service = _MockOdbcService();
    metrics = MetricsCollector()..clear();
    manager = OdbcBatchTransactionManager(service: service, metrics: metrics);
  });

  group('BatchTransactionGuard', () {
    test('invokes rollback once and not after markCommitted', () async {
      final guard = BatchTransactionGuard(5);
      var calls = 0;
      await guard.rollback((_) async => calls++);
      await guard.rollback((_) async => calls++);
      expect(calls, 1);
      expect(guard.isActive, isFalse);
    });

    test('does nothing for a null transaction id', () async {
      final guard = BatchTransactionGuard(null);
      var calls = 0;
      await guard.rollback((_) async => calls++);
      expect(calls, 0);
      expect(guard.isActive, isFalse);
    });

    test('markCommitted prevents subsequent rollback', () async {
      final guard = BatchTransactionGuard(7)..markCommitted();
      var calls = 0;
      await guard.rollback((_) async => calls++);
      expect(calls, 0);
    });
  });

  group('beginIfNeeded', () {
    test('returns a null-id start when transactions are disabled', () async {
      final result = await manager.beginIfNeeded(
        connectionId: 'c1',
        transactionEnabled: false,
        lockTimeout: null,
        accessMode: TransactionAccessMode.readWrite,
      );
      expect(result.getOrNull()?.transactionId, isNull);
      verifyNever(
        () => service.beginTransaction(
          any(),
          savepointDialect: any(named: 'savepointDialect'),
          accessMode: any(named: 'accessMode'),
          lockTimeout: any(named: 'lockTimeout'),
        ),
      );
    });

    test('starts a transaction and returns its id when enabled', () async {
      when(
        () => service.beginTransaction(
          any(),
          savepointDialect: any(named: 'savepointDialect'),
          accessMode: any(named: 'accessMode'),
          lockTimeout: any(named: 'lockTimeout'),
        ),
      ).thenAnswer((_) async => const Success(42));

      final result = await manager.beginIfNeeded(
        connectionId: 'c1',
        transactionEnabled: true,
        lockTimeout: const Duration(seconds: 3),
        accessMode: TransactionAccessMode.readOnly,
      );

      expect(result.getOrNull()?.transactionId, 42);
    });

    test('maps a begin failure to a transaction_begin QueryExecutionFailure', () async {
      when(
        () => service.beginTransaction(
          any(),
          savepointDialect: any(named: 'savepointDialect'),
          accessMode: any(named: 'accessMode'),
          lockTimeout: any(named: 'lockTimeout'),
        ),
      ).thenAnswer((_) async => Failure(Exception('begin boom')));

      final result = await manager.beginIfNeeded(
        connectionId: 'c1',
        transactionEnabled: true,
        lockTimeout: null,
        accessMode: TransactionAccessMode.readWrite,
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.Failure;
      expect(failure.context['operation'], 'transaction_begin');
      expect(failure.context['reason'], OdbcContextConstants.transactionFailedReason);
    });
  });

  group('commit', () {
    test('is a no-op for a non-transactional guard', () async {
      final result = await manager.commit(
        connectionId: 'c1',
        guard: BatchTransactionGuard(null),
      );
      expect(result.isSuccess(), isTrue);
      verifyNever(() => service.commitTransaction(any(), any()));
    });

    test('commits and marks the guard committed on success', () async {
      when(() => service.commitTransaction('c1', 9)).thenAnswer((_) async => const Success(unit));
      final guard = BatchTransactionGuard(9);

      final result = await manager.commit(connectionId: 'c1', guard: guard);

      expect(result.isSuccess(), isTrue);
      expect(guard.isActive, isFalse);
    });

    test('rolls back and fails when commit errors', () async {
      when(() => service.commitTransaction('c1', 11)).thenAnswer((_) async => Failure(Exception('commit boom')));
      when(() => service.rollbackTransaction('c1', 11)).thenAnswer((_) async => const Success(unit));
      final guard = BatchTransactionGuard(11);

      final result = await manager.commit(connectionId: 'c1', guard: guard);

      expect(result.isError(), isTrue);
      expect((result.exceptionOrNull()! as domain.Failure).context['operation'], 'transaction_commit');
      verify(() => service.rollbackTransaction('c1', 11)).called(1);
    });
  });

  group('rollbackTimeoutFromDeadline', () {
    test('falls back to the full timeout without a deadline', () {
      expect(manager.rollbackTimeoutFromDeadline(null), const Duration(seconds: 15));
    });

    test('clamps to the remaining time when it is shorter', () {
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      final timeout = manager.rollbackTimeoutFromDeadline(deadline);
      expect(timeout.inSeconds, lessThanOrEqualTo(2));
    });

    test('falls back to the full timeout when the deadline has elapsed', () {
      final deadline = DateTime.now().subtract(const Duration(seconds: 1));
      expect(manager.rollbackTimeoutFromDeadline(deadline), const Duration(seconds: 15));
    });
  });
}
