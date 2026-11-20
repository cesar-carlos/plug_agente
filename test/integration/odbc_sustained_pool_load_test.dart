import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';

import '../helpers/e2e_env.dart';
import '../helpers/odbc_e2e_coverage_sql.dart';
import '../helpers/odbc_e2e_rpc_harness.dart';

const _capacity = 4;
const _duration = Duration(seconds: 45);
const _options = SqlExecutionOptions(transaction: true, timeoutMs: 5000);

void main() async {
  await E2EEnv.load();
  for (final (engine, dsn) in [
    (OdbcE2eSqlDialect.sqlAnywhere, E2EEnv.odbcConnectionString),
    (OdbcE2eSqlDialect.sqlServer, E2EEnv.odbcSqlServerConnectionString),
  ]) {
    test(
      'sustained transactional pool load ${engine.name}',
      () async {
        final h = await OdbcE2eRpcHarness.open(dsn!, engine, poolSize: _capacity, useGatewayPoolPolicy: true);
        expect(h, isNotNull);
        final harness = h!;
        final pool = harness.connectionPool as IConnectionPoolDiagnostics;
        final sql = OdbcE2eCoverageSql(engine, tableName: odbcE2eUniqueTableName(prefix: 'plug_load'));
        var created = false;
        addTearDown(() async {
          try {
            await harness.shutdown();
          } finally {
            if (created) {
              // Cleanup also has to work when the load quarantined the original pool.
              final cleanup = (await OdbcE2eRpcHarness.open(dsn, engine, poolSize: _capacity))!;
              try {
                (await cleanup.gateway.executeNonQuery(
                  sql.dropTableIfExists,
                  null,
                  timeout: const Duration(seconds: 10),
                )).getOrThrow();
              } finally {
                await cleanup.shutdown();
              }
            }
          }
        });
        (await harness.gateway.executeNonQuery(sql.createTable, null)).getOrThrow();
        created = true;
        for (var id = 0; id < 12; id++) {
          final seed = sql.insertRow(
            id: id,
            code: 'worker$id',
            amt: 0,
            birthDate: '2024-01-01',
            ts: '2024-01-01 00:00:00',
            isActive: true,
          );
          expect((await harness.gateway.executeNonQuery(seed, null)).isSuccess(), isTrue);
        }
        var committed = 0;
        for (final clients in [2, 12]) {
          final latency = <int>[];
          final samples = <int>[];
          var directPeak = 0;
          final directBefore = harness.metrics.transactionalBatchDirectPathCount;
          final nativeBefore = harness.metrics.transactionalBatchNativePoolPathCount;
          var timeouts = 0;
          var errors = 0;
          final failureStages = <String, int>{};
          final timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
            final direct = harness.metrics.activeDirectConnections;
            if (direct > directPeak) directPeak = direct;
            samples.add((pool.getHealthDiagnostics()['tracked_owner_count']! as int) + direct);
          });
          final clock = Stopwatch()..start();
          try {
            await Future.wait(
              List.generate(clients, (id) async {
                final commands = [SqlCommand(sql: sql.updateAmtById(id, 1)), SqlCommand(sql: sql.updateAmtById(id, 1))];
                while (clock.elapsed < _duration && errors == 0 && timeouts == 0) {
                  final start = clock.elapsedMicroseconds;
                  final result = await harness.gateway.executeBatch(
                    'load-test',
                    commands,
                    options: _options,
                    timeout: const Duration(seconds: 5),
                  );
                  latency.add(clock.elapsedMicroseconds - start);
                  final error = result.exceptionOrNull();
                  if (error is Failure) {
                    final stage = (error.context['timeout_stage'] ?? error.context['operation'] ?? 'unspecified')
                        .toString();
                    failureStages.update(stage, (count) => count + 1, ifAbsent: () => 1);
                  }
                  if (error is Failure && error.context['timeout'] == true) {
                    timeouts++;
                  } else if (result.isError() ||
                      result.getOrThrow().length != 2 ||
                      !result.getOrThrow().every((item) => item.ok)) {
                    errors++;
                  } else {
                    committed++;
                  }
                }
              }),
            );
          } finally {
            timer.cancel();
            clock.stop();
          }
          latency.sort();
          int percentile(double p) => latency[(latency.length * p).ceil() - 1];
          final remaining =
              (pool.getHealthDiagnostics()['tracked_owner_count']! as int) + harness.metrics.activeDirectConnections;
          stdout.writeln(
            jsonEncode({
              'engine': engine.name,
              'capacity': _capacity,
              'clients': clients,
              'seconds': clock.elapsedMilliseconds / 1000,
              'attempts': latency.length,
              'p50_us': percentile(.50),
              'p95_us': percentile(.95),
              'p99_us': percentile(.99),
              'max_us': latency.last,
              'timeouts': timeouts,
              'errors': errors,
              'failure_stages': failureStages,
              'peak_leases': samples.isEmpty ? 0 : samples.reduce((a, b) => a > b ? a : b),
              'mean_leases': samples.isEmpty ? 0 : samples.reduce((a, b) => a + b) / samples.length,
              'leases_after': remaining,
              'direct_peak': directPeak,
              'direct_transactions': harness.metrics.transactionalBatchDirectPathCount - directBefore,
              'native_transactions': harness.metrics.transactionalBatchNativePoolPathCount - nativeBefore,
              'strategy': pool.getHealthDiagnostics()['effective_strategy'],
            }),
          );
          expect([timeouts, errors, remaining], [0, 0, 0]);
          expect(samples, isNotEmpty);
          expect(samples, everyElement(lessThanOrEqualTo(_capacity)));
          final recovery = await harness.gateway.executeQuery(
            QueryRequest(
              id: 'load-recovery',
              agentId: 'load-test',
              query: 'SELECT SUM(amt) AS total FROM ${sql.tableName}',
              timestamp: DateTime.now(),
            ),
            timeout: const Duration(seconds: 5),
          );
          expect(double.parse(recovery.getOrThrow().data.single.values.single.toString()), committed * 2);
        }
      },
      tags: ['live', 'perf'],
      skip: dsn == null || !E2EEnv.odbcRunLockContentionTests,
      timeout: const Timeout(Duration(minutes: 3)),
    );
    test(
      'sustained explicit pool checkout ${engine.name}',
      () async {
        final h = (await OdbcE2eRpcHarness.open(dsn!, engine, poolSize: _capacity))!;
        addTearDown(h.shutdown);
        final pool = h.connectionPool;
        final service = h.locator.asyncService;
        for (final clients in [2, 12]) {
          final elapsed = Stopwatch()..start();
          final latencies = <int>[];
          var inUse = 0;
          var peak = 0;
          await Future.wait(
            List.generate(clients, (_) async {
              while (elapsed.elapsed < const Duration(seconds: 30)) {
                final start = elapsed.elapsedMicroseconds;
                final id = (await pool.acquire(dsn)).getOrThrow();
                inUse++;
                if (inUse > peak) peak = inUse;
                try {
                  (await service.executeQuery('SELECT 1', connectionId: id)).getOrThrow();
                } finally {
                  (await pool.release(id)).getOrThrow();
                  inUse--;
                }
                latencies.add(elapsed.elapsedMicroseconds - start);
              }
            }),
          );
          latencies.sort();
          stdout.writeln(
            jsonEncode({
              'explicit_pool': engine.name,
              'clients': clients,
              'attempts': latencies.length,
              'seconds': elapsed.elapsedMilliseconds / 1000,
              'p95_us': latencies[(latencies.length * .95).ceil() - 1],
              'peak': peak,
              'remaining': inUse,
            }),
          );
          expect(peak, inInclusiveRange(1, _capacity));
          expect(inUse, 0);
          expect((await pool.getActiveCount()).getOrThrow(), 0);
        }
      },
      tags: ['live', 'perf'],
      skip: dsn == null || !E2EEnv.odbcRunLockContentionTests,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
