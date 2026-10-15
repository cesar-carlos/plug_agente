import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_emitter.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

class _NativeService extends Mock implements OdbcService {}

void main() {
  test('measures polling detection and incremental columnar row delivery', () async {
    final results = <Map<String, Object?>>[];
    for (final readyAfterMs in [1, 5, 50, 200]) {
      final service = _NativeService();
      final metrics = MetricsCollector();
      final executor = OdbcStatementExecutor(
        service: service,
        metrics: metrics,
        markConnectionForDiscard: (_) => fail('Unexpected connection discard'),
      );
      final nativeWatch = Stopwatch();
      var polls = 0;
      when(() => service.executeAsyncStart('fixture', 'SELECT 1')).thenAnswer((_) async {
        nativeWatch
          ..reset()
          ..start();
        return const Success(1);
      });
      when(() => service.asyncPoll(1)).thenAnswer((_) async {
        polls++;
        return Success(nativeWatch.elapsedMilliseconds >= readyAfterMs ? 1 : 0);
      });
      when(() => service.asyncGetResult(1)).thenAnswer(
        (_) async => const Success(
          QueryResult(
            columns: ['value'],
            rows: [
              [1],
            ],
            rowCount: 1,
          ),
        ),
      );
      when(() => service.asyncFree(1)).thenAnswer((_) async => const Success(unit));
      final elapsed = <int>[];
      final pollCounts = <int>[];
      for (var sample = 0; sample < 25; sample++) {
        polls = 0;
        final watch = Stopwatch()..start();
        final result = await executor.runNativeAsyncQueryWithTimeout(
          connectionId: 'fixture',
          query: 'SELECT 1',
          timeout: const Duration(seconds: 3),
        );
        watch.stop();
        expect(result.isSuccess(), isTrue);
        if (sample >= 5) {
          elapsed.add(watch.elapsedMicroseconds);
          pollCounts.add(polls);
        }
      }
      results.add({
        'name': 'poll_ready_${readyAfterMs}ms',
        ...percentiles(elapsed),
        'mean_polls': pollCounts.reduce((a, b) => a + b) / pollCounts.length,
      });
      metrics.dispose();
    }
    final input = toTypedColumnar(
      QueryResult(
        columns: List.generate(8, (i) => 'column_$i'),
        rows: List.generate(10000, (row) => List.generate(8, (column) => row + column)),
        rowCount: 10000,
      ),
    );
    for (final cancelAfterFirst in [false, true]) {
      final first = <int>[];
      final total = <int>[];
      for (var sample = 0; sample < 25; sample++) {
        var rows = 0;
        var firstUs = 0;
        var cancelled = false;
        final watch = Stopwatch()..start();
        await OdbcColumnarStreamChunkEmitter.emit(
          result: input,
          fetchSize: 1000,
          onChunk: (chunk) async {
            if (rows == 0) firstUs = watch.elapsedMicroseconds;
            rows += chunk.length;
            cancelled = cancelAfterFirst;
          },
          isCancelRequested: () => cancelled,
        );
        watch.stop();
        expect(rows, cancelAfterFirst ? 1000 : 10000);
        if (sample >= 5) {
          first.add(firstUs);
          total.add(watch.elapsedMicroseconds);
        }
      }
      results.add({
        'name': cancelAfterFirst ? 'stream_cancel_first' : 'stream_complete',
        'first_chunk': percentiles(first),
        'total': percentiles(total),
      });
    }
    final report = jsonEncode({
      'benchmark': 'odbc_polling_streaming',
      'native_io': 'simulated',
      'warmup': 5,
      'samples': 20,
      'results': results,
    });
    final output = Platform.environment['ODBC_POLLING_STREAMING_OUTPUT'];
    if (output != null) File(output).writeAsStringSync(report);
    // ignore: avoid_print
    print(report);
  }, tags: ['perf']);
}

Map<String, Object> percentiles(List<int> samples) {
  samples.sort();
  return {'p50_us': samples[samples.length ~/ 2], 'p95_us': samples[(samples.length * .95).ceil() - 1]};
}
