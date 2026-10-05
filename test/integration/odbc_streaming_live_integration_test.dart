import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_gateway.dart';

import '../helpers/e2e_env.dart';
import '../helpers/mock_odbc_connection_settings.dart';

void main() async {
  await E2EEnv.load();

  final connectionString = E2EEnv.odbcConnectionStringAny;
  final connectionStringValid = connectionString != null && connectionString.trim().isNotEmpty;
  final smokeQuery = E2EEnv.odbcSmokeQuery;
  final longRunningQuery = E2EEnv.odbcLongQuery;
  final longQueryValid = longRunningQuery != null && longRunningQuery.trim().isNotEmpty;

  group('ODBC streaming live integration', () {
    late odbc.ServiceLocator locator;
    late OdbcStreamingGateway gateway;
    var isReady = false;

    setUpAll(() async {
      if (connectionString == null || connectionString.trim().isEmpty) {
        return;
      }

      final settings = MockOdbcConnectionSettings();
      locator = createAsyncOdbcServiceLocatorForSettings(settings);
      final service = locator.asyncService;
      final initResult = await service.initialize();
      if (initResult.isError()) {
        return;
      }

      gateway = OdbcStreamingGateway(service, settings);
      isReady = true;
    });

    tearDownAll(() {
      if (isReady) {
        locator.shutdown();
      }
    });

    test(
      'should stream rows with a real DSN',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );

        var totalRows = 0;
        final result = await gateway.executeQueryStream(
          smokeQuery,
          connectionString!,
          (chunk) async {
            totalRows += chunk.length;
          },
          fetchSize: 1,
        );

        expect(result.isSuccess(), isTrue);
        expect(totalRows, greaterThan(0));
      },
      skip: !connectionStringValid
          ? 'Defina ODBC_TEST_DSN, ODBC_TEST_DSN_SQL_SERVER ou ODBC_TEST_DSN_POSTGRESQL no .env'
          : false,
      tags: const ['live'],
    );

    test(
      'should support cancellation with long-running query',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );
        expect(longQueryValid, isTrue, reason: 'Long query not configured');

        final query = longRunningQuery!;
        final firstChunk = Completer<void>();
        final releaseConsumer = Completer<void>();
        var deliveredChunks = 0;
        final execution = gateway.executeQueryStream(
          query,
          connectionString!,
          (_) async {
            deliveredChunks++;
            if (!firstChunk.isCompleted) firstChunk.complete();
            await releaseConsumer.future;
          },
          fetchSize: 50,
        );

        // Synchronize with a live cursor instead of polling a potentially short
        // query. Backpressure keeps the connection active until cancellation.
        try {
          await Future.any([
            firstChunk.future,
            execution.then((result) {
              if (!firstChunk.isCompleted) {
                throw StateError('Streaming ended before its first chunk (success=${result.isSuccess()})');
              }
            }),
          ]).timeout(const Duration(seconds: 15));
          expect(gateway.hasActiveStream, isTrue);
          final cancellation = gateway.cancelActiveStream();
          releaseConsumer.complete();
          expect((await cancellation).isSuccess(), isTrue);
        } finally {
          if (!releaseConsumer.isCompleted) releaseConsumer.complete();
        }

        final result = await execution.timeout(const Duration(seconds: 20));
        expect(result.isError(), isTrue);
        expect(deliveredChunks, 1);
        expect(gateway.hasActiveStream, isFalse);
      },
      skip: !connectionStringValid || !longQueryValid
          ? 'Defina um DSN e ODBC_INTEGRATION_LONG_QUERY* (query longa) no .env'
          : false,
      tags: const ['live', 'slow'],
    );
  });
}
