import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

import '../helpers/e2e_env.dart';
import '../helpers/odbc_e2e_coverage_sql.dart';
import '../helpers/odbc_e2e_row_assertions.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';

/// E2E opt-in: validates the `sql.execute` path for:
/// `SELECT TOP 1 CodCliente FROM Cliente ORDER BY CodCliente`.
///
/// Enabled only when:
/// - `ODBC_E2E_CODCLIENTE_TESTS=true`
/// - a DSN is available through `E2EEnv.odbcE2eRpcConnectionString`
void main() async {
  await E2EEnv.load();

  final dsn = E2EEnv.odbcE2eRpcConnectionString;
  final dsnValid = dsn != null && dsn.trim().isNotEmpty;
  final enabled = E2EEnv.odbcE2eCodClienteTests;
  final sql = E2EEnv.odbcE2eCodClienteQuery;

  final skipMessage = !dsnValid
      ? 'Defina ODBC_E2E_RPC_DSN ou pelo menos um de ODBC_TEST_DSN / ODBC_DSN, '
            'ODBC_TEST_DSN_SQL_SERVER, ODBC_TEST_DSN_POSTGRESQL no .env.'
      : !enabled
      ? 'Defina ODBC_E2E_CODCLIENTE_TESTS=true no .env para habilitar este E2E.'
      : null;

  group('ODBC sql.execute CodCliente probe (live E2E)', () {
    OdbcE2eRpcHarness? harness;
    var isReady = false;

    setUpAll(() async {
      if (!dsnValid || !enabled) {
        return;
      }
      final connectionString = dsn;
      final opened = await OdbcE2eRpcHarness.open(
        connectionString,
        detectOdbcE2eDialect(connectionString),
      );
      if (opened == null) {
        return;
      }
      harness = opened;
      isReady = true;
    });

    tearDownAll(() async {
      await harness?.shutdown();
    });

    test(
      'should execute TOP 1 CodCliente query with expected response shape',
      () async {
        expect(
          isReady,
          isTrue,
          reason: 'ODBC init failed or env not configured for CodCliente E2E',
        );
        final h = harness!;

        final request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'e2e-codcliente-top1',
          params: <String, dynamic>{
            'sql': sql,
            'options': {'max_rows': 1},
          },
        );

        final response = await h.dispatcher.dispatch(request, 'e2e-agent');
        expect(response.isSuccess, isTrue, reason: '${response.error}');

        final payload = response.result! as Map<String, dynamic>;
        final rows = payload['rows'] as List<dynamic>? ?? const <dynamic>[];
        expect(
          rows.length,
          lessThanOrEqualTo(1),
          reason: 'TOP 1 should return at most one row, got ${rows.length}.',
        );

        if (rows.isNotEmpty) {
          final row = Map<String, dynamic>.from(rows.first as Map<dynamic, dynamic>);
          final codCliente = e2eRowStringForColumnInsensitive(row, 'codcliente');
          expect(
            codCliente,
            isNotNull,
            reason: 'Expected CodCliente column in row. Keys: ${row.keys}',
          );
        }
      },
      skip: skipMessage,
      tags: const ['live'],
    );
  });
}
