import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import '../helpers/mock_odbc_connection_settings.dart';

/// FFI-safe pool-mode smoke benchmark (use instead of plain `dart run` tools).
void main() {
  final connectionString = Platform.environment['ODBC_BENCH_CONNECTION_STRING']?.trim();
  final skipReason = connectionString == null || connectionString.isEmpty
      ? 'Set ODBC_BENCH_CONNECTION_STRING to run pool mode benchmark smoke.'
      : null;

  test(
    'odbc pool modes benchmark smoke',
    () async {
      final locator = ServiceLocator()..initialize(useAsync: true);
      try {
        final service = locator.asyncService;
        final initResult = await service.initialize();
        expect(initResult.isSuccess(), isTrue, reason: initResult.exceptionOrNull()?.toString());

        final settings = MockOdbcConnectionSettings(poolSize: 4);
        final pool = OdbcConnectionPool(service, settings);
        final acquired = await pool.acquire(connectionString!);
        expect(acquired.isSuccess(), isTrue, reason: acquired.exceptionOrNull()?.toString());

        final connectionId = acquired.getOrThrow();
        try {
          final queryResult = await service.executeQuery('SELECT 1', connectionId: connectionId);
          expect(queryResult.isSuccess(), isTrue, reason: queryResult.exceptionOrNull()?.toString());
        } finally {
          await pool.release(connectionId);
          await pool.closeAll();
        }
      } finally {
        locator.shutdown();
      }
    },
    skip: skipReason,
  );
}
