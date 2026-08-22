import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/benchmarks/odbc_transaction_control_benchmark_lib.dart';
import '../helpers/e2e_env.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await E2EEnv.load();

  final dsn = E2EEnv.odbcConnectionStringAny;
  final skipReason = dsn == null || dsn.isEmpty
      ? 'Set ODBC_TEST_DSN or ODBC_DSN to run transaction control benchmark.'
      : null;

  test(
    'odbc transaction control benchmark',
    () async {
      final payload = await runOdbcTransactionControlBenchmark(
        dsn: dsn!,
        iterations: 4,
      );

      expect(payload, isNotNull);
      stdout.writeln(jsonEncode(payload));
      expect(payload!['autocommit_select_median_us'], isA<int>());
      expect(payload['begin_select_commit_median_us'], isA<int>());
      expect(payload['begin_select_rollback_median_us'], isA<int>());
    },
    skip: skipReason,
    timeout: Timeout.none,
    tags: const ['perf'],
  );
}
