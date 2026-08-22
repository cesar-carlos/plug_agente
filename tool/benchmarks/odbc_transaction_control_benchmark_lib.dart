import 'dart:io';

import 'package:odbc_fast/odbc_fast.dart';

Future<Map<String, Object?>?> runOdbcTransactionControlBenchmark({
  required String dsn,
  int iterations = 8,
}) async {
  final locator = ServiceLocator()
    ..initialize(
      useAsync: true,
      asyncWorkerCount: 2,
      asyncMaxPendingRequests: 8,
      asyncBackpressureMode: AsyncBackpressureMode.failFast,
    );
  final service = locator.service;

  try {
    final init = await service.initialize();
    if (init.isError()) {
      stderr.writeln('ODBC init failed: ${init.exceptionOrNull()}');
      return null;
    }

    final connect = await service.connect(dsn);
    if (connect.isError()) {
      stderr.writeln('ODBC connect failed: ${connect.exceptionOrNull()}');
      return null;
    }
    final connectionId = connect.getOrThrow().id;

    try {
      final autocommitUs = await _medianMicros(iterations, () async {
        final result = await service.executeQuery('SELECT 1', connectionId: connectionId);
        if (result.isError()) {
          throw result.exceptionOrNull()!;
        }
      });

      final commitUs = await _medianMicros(iterations, () async {
        final begin = await service.beginTransaction(
          connectionId,
          savepointDialect: SavepointDialect.auto,
          accessMode: TransactionAccessMode.readWrite,
        );
        if (begin.isError()) {
          throw begin.exceptionOrNull()!;
        }
        final txnId = begin.getOrThrow();
        final query = await service.executeQuery('SELECT 1', connectionId: connectionId);
        if (query.isError()) {
          await service.rollbackTransaction(connectionId, txnId);
          throw query.exceptionOrNull()!;
        }
        final commit = await service.commitTransaction(connectionId, txnId);
        if (commit.isError()) {
          await service.rollbackTransaction(connectionId, txnId);
          throw commit.exceptionOrNull()!;
        }
      });

      final rollbackUs = await _medianMicros(iterations, () async {
        final begin = await service.beginTransaction(
          connectionId,
          savepointDialect: SavepointDialect.auto,
          accessMode: TransactionAccessMode.readWrite,
        );
        if (begin.isError()) {
          throw begin.exceptionOrNull()!;
        }
        final txnId = begin.getOrThrow();
        final query = await service.executeQuery('SELECT 1', connectionId: connectionId);
        if (query.isError()) {
          await service.rollbackTransaction(connectionId, txnId);
          throw query.exceptionOrNull()!;
        }
        final rollback = await service.rollbackTransaction(connectionId, txnId);
        if (rollback.isError()) {
          throw rollback.exceptionOrNull()!;
        }
      });

      return {
        'dsn_configured': true,
        'iterations': iterations,
        'autocommit_select_median_us': autocommitUs,
        'begin_select_commit_median_us': commitUs,
        'begin_select_rollback_median_us': rollbackUs,
      };
    } finally {
      await service.disconnect(connectionId);
    }
  } finally {
    locator.shutdown();
  }
}

Future<int> _medianMicros(int iterations, Future<void> Function() action) async {
  await action();
  final samples = <int>[];
  for (var i = 0; i < iterations; i++) {
    final watch = Stopwatch()..start();
    await action();
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}
