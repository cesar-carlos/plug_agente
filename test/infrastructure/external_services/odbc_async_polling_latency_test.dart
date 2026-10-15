import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

class _Service extends Mock implements OdbcService {}

void main() {
  for (final readyAfter in [const Duration(milliseconds: 1), const Duration(seconds: 1)]) {
    test('detects completion at $readyAfter with bounded polling', () {
      fakeAsync((async) {
        final service = _Service();
        final metrics = MetricsCollector();
        final executor = OdbcStatementExecutor(
          service: service,
          metrics: metrics,
          markConnectionForDiscard: (_) => fail('Unexpected discard'),
        );
        var polls = 0;
        var finished = false;
        when(() => service.executeAsyncStart('c', 'SELECT 1')).thenAnswer((_) async => const Success(1));
        when(() => service.asyncPoll(1)).thenAnswer((_) async {
          polls++;
          return Success(async.elapsed >= readyAfter ? 1 : 0);
        });
        when(() => service.asyncGetResult(1)).thenAnswer(
          (_) async => const Success(
            QueryResult(
              columns: ['v'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          ),
        );
        when(() => service.asyncFree(1)).thenAnswer((_) async => const Success(unit));
        executor
            .runNativeAsyncQueryWithTimeout(connectionId: 'c', query: 'SELECT 1', timeout: const Duration(seconds: 10))
            .then((result) {
              expect(result.isSuccess(), isTrue);
              finished = true;
            });
        async.flushMicrotasks();
        async.elapse(readyAfter + Duration(milliseconds: readyAfter.inSeconds == 0 ? 2 : 20));
        expect(finished, isTrue);
        expect(polls, lessThanOrEqualTo(readyAfter.inSeconds == 0 ? 3 : 55));
        verify(() => service.executeAsyncStart('c', 'SELECT 1')).called(1);
        verify(() => service.asyncFree(1)).called(1);
        metrics.dispose();
      });
    });
  }
}
