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

      locator = odbc.ServiceLocator()..initialize(useAsync: true);
      final service = locator.asyncService;
      final initResult = await service.initialize();
      if (initResult.isError()) {
        return;
      }

      gateway = OdbcStreamingGateway(service, MockOdbcConnectionSettings());
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

        const waitForActive = Duration(seconds: 15);
        final deadline = DateTime.now().add(waitForActive);
        while (!gateway.hasActiveStream && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(
          gateway.hasActiveStream,
          isTrue,
          reason:
              'Streaming did not become active before cancel (check DSN, long query, or connect latency)',
        );

        final cancelResult = await gateway.cancelActiveStream();
        expect(cancelResult.isSuccess(), isTrue);

        final result = await execution.timeout(const Duration(seconds: 20));
        expect(result.isError(), isTrue);
      },
      skip: !connectionStringValid || !longQueryValid
          ? 'Defina um DSN e ODBC_INTEGRATION_LONG_QUERY* (query longa) no .env'
          : false,
    );
  });
}
