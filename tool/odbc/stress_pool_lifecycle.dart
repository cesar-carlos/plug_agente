import 'dart:convert';
import 'dart:io';

import 'package:odbc_fast/infrastructure/repositories/odbc_repository_impl.dart';
import 'package:odbc_fast/odbc_fast.dart';

/// Opt-in diagnostic: IDs correlate each successful checkout with its return.
/// No connection string or credentials enter the report.
Future<void> main() async {
  final dsn = Platform.environment['ODBC_TEST_DSN'];
  if (dsn == null || dsn.isEmpty) throw StateError('Diagnostic DSN unavailable');
  final locator = ServiceLocator()..initialize(useAsync: true, asyncWorkerCount: 4);
  final service = locator.asyncService;
  (await service.initialize()).getOrThrow();
  final repository = locator.repository as OdbcRepositoryImpl;
  final pool = (await service.poolCreate(dsn, 20)).getOrThrow();
  final snapshots = <Map<String, Object?>>[];
  final events = <Map<String, Object>>[];
  final acquisitions = <String>{};
  final confirmedReturns = <String>{};
  try {
    for (var round = 0; round < 10; round++) {
      // Never queue more blocking checkouts than pool capacity on the workers.
      await Future.wait(
        List.generate(20, (worker) async {
          for (var iteration = 0; iteration < 10; iteration++) {
            final connection = (await service.poolGetConnection(pool)).getOrThrow();
            if (!acquisitions.add(connection.id)) throw StateError('Checkout ID was reused');
            events.add({'event': 'acquire', 'round': round, 'worker': worker, 'id': connection.id});
            try {
              final result = (await service.executeQuery('SELECT 1 AS v', connectionId: connection.id)).getOrThrow();
              if (result.rows.single.single != 1) throw StateError('Query result differs');
            } finally {
              (await service.poolReleaseConnection(connection.id)).getOrThrow();
            }
            if (!confirmedReturns.add(connection.id)) throw StateError('Duplicate confirmed return');
            events.add({'event': 'release_confirmed', 'round': round, 'worker': worker, 'id': connection.id});
          }
        }),
      );
      final logical = repository.dartSideMetrics().toJson();
      final native = (await service.poolGetStateDetailed(pool)).getOrThrow();
      if (logical['connectionCount'] != 0 ||
          logical['poolCheckoutCount'] != 0 ||
          native['active_connections'] != 0 ||
          native['checked_out_count'] != 0 ||
          native['checkout_pending'] != false ||
          native['release_pending'] != false) {
        throw StateError('Confirmed work left outstanding connections');
      }
      snapshots.add({'round': round + 1, 'logical': logical, 'native': native});
    }
    if (acquisitions.length != 2000 || !confirmedReturns.containsAll(acquisitions)) {
      throw StateError('Checkout and confirmed return events differ');
    }
  } finally {
    try {
      (await service.poolClose(pool)).getOrThrow();
    } finally {
      locator.shutdown();
    }
  }
  stdout.writeln(jsonEncode({'diagnostic': 'pool_lifecycle_v1', 'rounds': snapshots, 'events': events}));
}
