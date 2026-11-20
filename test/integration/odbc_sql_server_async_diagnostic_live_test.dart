import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/logging/file_log_sink.dart';

import '../helpers/e2e_env.dart';
import '../helpers/odbc_e2e_coverage_sql.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';

void main() async {
  await E2EEnv.load();
  final dsn = E2EEnv.odbcSqlServerConnectionString;
  const sql = 'SELECT CAST(1 AS date) AS invalid_date';
  group('SQL Server async diagnostic', () {
    late OdbcE2eRpcHarness harness;
    setUp(() async {
      harness = (await OdbcE2eRpcHarness.open(dsn!, OdbcE2eSqlDialect.sqlServer))!;
      addTearDown(harness.shutdown);
    });

    test('poll exposes the driver diagnostic and preserves it for getResult', () async {
      final service = harness.locator.asyncService;
      final connection = (await service.connect(dsn!)).getOrThrow();
      addTearDown(() => service.disconnect(connection.id));
      final request = (await service.executeAsyncStart(connection.id, sql)).getOrThrow();
      addTearDown(() => service.asyncFree(request));
      final deadline = Stopwatch()..start();
      while (true) {
        final poll = await service.asyncPoll(request);
        if (poll.isError()) {
          final error = poll.exceptionOrNull()! as odbc.OdbcError;
          expect(error.sqlState, '22018', reason: error.message);
          expect(error.nativeCode, 529);
          break;
        }
        expect(poll.getOrThrow(), 0);
        expect(deadline.elapsed, lessThan(const Duration(seconds: 5)));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final error = (await service.asyncGetResult(request)).exceptionOrNull()! as odbc.OdbcError;
      expect(error.sqlState, '22018');
      expect(error.nativeCode, 529);
    }, tags: ['live']);

    test('sql.execute writes both driver codes to the agent error log', () async {
      final directory = await Directory.systemTemp.createTemp('odbc-diagnostic-');
      addTearDown(() => directory.delete(recursive: true));
      final sink = FileLogSink(logDirectoryPath: directory.path);
      await sink.open();
      addTearDown(sink.close);
      AppLogger.attachStructuredSink(sink);
      addTearDown(AppLogger.detachStructuredSink);
      final response = await harness.dispatcher.dispatch(
        const RpcRequest(jsonrpc: '2.0', id: 'async-diag', method: 'sql.execute', params: {'sql': sql}),
        'e2e-agent',
      );
      expect(response.error, isNotNull);
      final contexts = (await File(sink.logFilePath).readAsLines())
          .where((line) => line.contains(' | context='))
          .map((line) => jsonDecode(line.split(' | context=')[1].split(' | ')[0]) as Map<String, dynamic>);
      expect(
        contexts,
        contains(
          predicate<Map<String, dynamic>>(
            (c) => c['operation'] == 'sql.execute' && c['odbc_sql_state'] == '22018' && c['odbc_native_code'] == 529,
          ),
        ),
      );
    }, tags: ['live']);
  }, skip: dsn == null);
}
