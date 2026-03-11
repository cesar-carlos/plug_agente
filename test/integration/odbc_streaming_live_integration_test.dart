import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_gateway.dart';
import '../helpers/mock_odbc_connection_settings.dart';

void main() {
  group('ODBC streaming live integration', () {
    final connectionString =
        Platform.environment['ODBC_TEST_DSN'] ??
        Platform.environment['ODBC_DSN'];
    final smokeQuery =
        Platform.environment['ODBC_INTEGRATION_SMOKE_QUERY'] ?? 'SELECT 1';
    final longRunningQuery =
        Platform.environment['ODBC_INTEGRATION_LONG_QUERY'];

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
        if (!isReady) {
          return;
        }

        var totalRows = 0;
        final result = await gateway.executeQueryStream(
          smokeQuery,
          connectionString!,
          (chunk) {
            totalRows += chunk.length;
          },
          fetchSize: 1,
        );

        expect(result.isSuccess(), isTrue);
        expect(totalRows, greaterThan(0));
      },
      skip: connectionString == null ? 'Set ODBC_TEST_DSN or ODBC_DSN' : false,
    );

    test(
      'should support cancellation with long-running query',
      () async {
        if (!isReady || longRunningQuery == null || longRunningQuery.isEmpty) {
          return;
        }

        final execution = gateway.executeQueryStream(
          longRunningQuery,
          connectionString!,
          (_) {},
          fetchSize: 50,
        );

        await Future<void>.delayed(const Duration(milliseconds: 250));
        final cancelResult = await gateway.cancelActiveStream();
        expect(cancelResult.isSuccess(), isTrue);

        final result = await execution.timeout(const Duration(seconds: 20));
        expect(result.isError(), isTrue);
      },
      skip: connectionString == null || longRunningQuery == null
          ? 'Set ODBC_TEST_DSN/ODBC_DSN and ODBC_INTEGRATION_LONG_QUERY'
          : false,
    );
  });
}
