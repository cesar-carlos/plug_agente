import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_in_flight_execution_abort_service.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_in_flight_execution_registry.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

class _MockOdbcService extends Mock implements OdbcService {}

void main() {
  setUpAll(() {
    registerFallbackValue(const StatementOptions());
  });

  late _MockOdbcService service;
  late OdbcInFlightExecutionRegistry registry;
  late OdbcInFlightExecutionAbortService abortService;
  late List<String> discarded;

  setUp(() {
    service = _MockOdbcService();
    registry = OdbcInFlightExecutionRegistry();
    discarded = <String>[];
    final statementExecutor = OdbcStatementExecutor(
      service: service,
      metrics: MetricsCollector()..clear(),
      markConnectionForDiscard: discarded.add,
    );
    abortService = OdbcInFlightExecutionAbortService(
      registry: registry,
      statementExecutor: statementExecutor,
      markConnectionForDiscard: discarded.add,
    );
  });

  test('abortInFlightExecution cancels prepared statement when registered', () async {
    registry.register(
      'req-1',
      const OdbcInFlightExecutionHandle(connectionId: 'conn-1', statementId: 7),
    );
    when(() => service.cancelStatement('conn-1', 7)).thenAnswer((_) async => const Success(unit));

    final result = await abortService.abortInFlightExecution('req-1');

    expect(result.getOrNull(), isTrue);
    verify(() => service.cancelStatement('conn-1', 7)).called(1);
  });

  test('abortInFlightExecution returns false when request is not registered', () async {
    final result = await abortService.abortInFlightExecution('missing');

    expect(result.getOrNull(), isFalse);
    verifyNever(() => service.cancelStatement(any(), any()));
    verifyNever(() => service.asyncCancel(any()));
  });

  test('abortInFlightExecution marks connection when no native target exists', () async {
    registry.register(
      'req-1',
      const OdbcInFlightExecutionHandle(connectionId: 'conn-1'),
    );

    final result = await abortService.abortInFlightExecution('req-1');

    expect(result.getOrNull(), isTrue);
    expect(discarded, contains('conn-1'));
  });
}
