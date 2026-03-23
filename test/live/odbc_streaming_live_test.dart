@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_gateway.dart';

import '../helpers/e2e_env.dart';
import '../helpers/live_test_env.dart';
import '../helpers/mock_odbc_connection_settings.dart';
import '../helpers/odbc_live_bootstrap.dart';

void main() async {
  await loadLiveTestEnv();

  final connectionString = E2EEnv.odbcConnectionStringAny;
  final connectionStringValid =
      connectionString != null && connectionString.trim().isNotEmpty;
  final smokeQuery = E2EEnv.odbcSmokeQuery;
  final longRunningQuery =
      connectionString != null && connectionString.trim().isNotEmpty
      ? E2EEnv.odbcLongQueryForDsn(connectionString)
      : null;
  final longQueryValid =
      longRunningQuery != null && longRunningQuery.trim().isNotEmpty;

  group('ODBC streaming live', () {
    OdbcLiveBootstrap? bootstrap;
    late OdbcStreamingGateway gateway;
    var isReady = false;

    setUpAll(() async {
      if (connectionString == null || connectionString.trim().isEmpty) {
        return;
      }

      final opened = await OdbcLiveBootstrap.open();
      if (opened == null) {
        return;
      }
      bootstrap = opened;
      gateway = OdbcStreamingGateway(
        opened.asyncService,
        MockOdbcConnectionSettings(),
      );
      isReady = true;
    });

    tearDownAll(() {
      bootstrap?.shutdown();
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
      skip: E2EEnv.skipUnless(
        connectionStringValid,
        E2EEnv.skipReasonNoOdbcDsnAny,
      ),
    );

    test(
      'should deliver multiple rows across chunks when fetchSize is 1',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or DSN not configured',
        );

        const unionProbe =
            'SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3';
        var chunkEvents = 0;
        var totalRows = 0;
        final result = await gateway.executeQueryStream(
          unionProbe,
          connectionString!,
          (List<Map<String, dynamic>> chunk) async {
            chunkEvents++;
            totalRows += chunk.length;
          },
          fetchSize: 1,
        );

        expect(result.isSuccess(), isTrue, reason: '$result');
        expect(totalRows, 3);
        expect(chunkEvents, greaterThanOrEqualTo(3));
      },
      skip: E2EEnv.skipUnless(
        connectionStringValid,
        E2EEnv.skipReasonNoOdbcDsnAny,
      ),
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
        final execution = gateway.executeQueryStream(
          query,
          connectionString!,
          (_) async {},
          fetchSize: 50,
        );

        await Future<void>.delayed(const Duration(milliseconds: 250));
        final cancelResult = await gateway.cancelActiveStream();
        expect(cancelResult.isSuccess(), isTrue);

        final result = await execution.timeout(const Duration(seconds: 20));
        expect(result.isError(), isTrue);
      },
      skip: E2EEnv.skipUnless(
        connectionStringValid && longQueryValid,
        E2EEnv.skipReasonOdbcLongQuery,
      ),
    );
  });
}
