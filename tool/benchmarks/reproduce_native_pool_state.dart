// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:odbc_fast/odbc_fast_native.dart';

/// Minimal upstream reproducer: concurrent checkouts, confirmed returns, state.
Future<void> main(List<String> args) async {
  final dsn = Platform.environment['ODBC_TEST_DSN'];
  if (dsn == null || dsn.isEmpty) throw StateError('ODBC_TEST_DSN required');
  final native = AsyncNativeOdbcConnection(workerCount: 8, maxPendingRequests: 256);
  await native.initialize();
  final pool = await native.poolCreate(dsn, 20);
  if (pool == 0) throw StateError('Pool creation failed');
  try {
    for (var round = 0; round < 10; round++) {
      // Fewer checkouts than pool capacity, with all returns awaited.
      await Future.wait(
        List.generate(8, (_) async {
          final connection = await native.poolGetConnection(pool);
          if (connection == 0) throw StateError('Checkout failed');
          var returned = true;
          try {
            if (args.contains('--prepared-transaction')) {
              final transaction = await native.beginTransaction(connection, IsolationLevel.readCommitted.value);
              if (transaction == 0) throw StateError('Begin failed');
              final statement = await native.prepare(connection, 'SELECT 1');
              if (statement == 0) throw StateError('Prepare failed');
              final result = await native.executePrepared(statement, const <ParamValue>[], 0, 1000);
              if (result == null) throw StateError('Prepared query failed');
              if (!await native.closeStatement(statement)) throw StateError('Statement close failed');
              if (!await native.commitTransaction(transaction)) throw StateError('Commit failed');
            } else {
              final request = await native.executeAsyncStart(connection, 'SELECT 1');
              if (request == 0) throw StateError('Async start failed');
              var status = await native.asyncPoll(request);
              final deadline = DateTime.now().add(const Duration(seconds: 30));
              while (status == 0 && DateTime.now().isBefore(deadline)) {
                await Future<void>.delayed(const Duration(milliseconds: 1));
                status = await native.asyncPoll(request);
              }
              if (status != 1) throw StateError('Async request did not complete');
              final result = await native.asyncGetResult(request);
              if (!await native.asyncFree(request)) throw StateError('Async free failed');
              if (result == null) throw StateError('Query failed');
            }
          } finally {
            returned = await native.poolReleaseConnection(connection);
          }
          if (!returned) throw StateError('Return failed');
        }),
      );
      final raw = await native.poolGetStateJson(pool);
      if (raw == null) throw StateError('State unavailable');
      final state = jsonDecode(raw) as Map<String, dynamic>;
      print(jsonEncode({'round': round, ...state}));
      if (state['active_connections'] != 0) {
        exitCode = 1;
        return;
      }
    }
  } finally {
    await native.poolClose(pool);
    native.dispose();
  }
}
