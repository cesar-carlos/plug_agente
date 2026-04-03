import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/metrics/odbc_native_metrics_service.dart';
import 'package:result_dart/result_dart.dart';

class MockOdbcService extends Mock implements OdbcService {}

void main() {
  group('OdbcNativeMetricsService', () {
    late MockOdbcService mockService;
    late OdbcNativeMetricsService service;

    setUp(() {
      mockService = MockOdbcService();
      service = OdbcNativeMetricsService(mockService);
    });

    test('should return merged snapshot when native calls succeed', () async {
      when(() => mockService.getMetrics()).thenAnswer(
        (_) async => const Success(
          OdbcMetrics(
            queryCount: 10,
            errorCount: 2,
            uptimeSecs: 100,
            totalLatencyMillis: 420,
            avgLatencyMillis: 42,
          ),
        ),
      );
      when(() => mockService.getPreparedStatementsMetrics()).thenAnswer(
        (_) async => const Success(
          PreparedStatementMetrics(
            cacheSize: 4,
            cacheMaxSize: 16,
            cacheHits: 20,
            cacheMisses: 5,
            totalPrepares: 8,
            totalExecutions: 80,
            memoryUsageBytes: 4096,
            avgExecutionsPerStmt: 10.0,
          ),
        ),
      );

      final result = await service.collectSnapshot();

      expect(result.isSuccess(), isTrue);
      final snapshot = result.getOrThrow();
      expect(snapshot['engine'], isA<Map<String, dynamic>>());
      expect(snapshot['prepared_statements'], isA<Map<String, dynamic>>());
      final engine = snapshot['engine'] as Map<String, dynamic>;
      final prepared = snapshot['prepared_statements'] as Map<String, dynamic>;
      expect(engine['query_count'], 10);
      expect(engine['avg_latency_millis'], 42);
      expect(prepared['cache_hits'], 20);
      expect(prepared['cache_hit_rate'], closeTo(80.0, 0.0001));
    });

    test('should return typed failure when getMetrics fails', () async {
      when(() => mockService.getMetrics()).thenAnswer(
        (_) async => const Failure(
          ConnectionError(message: 'native metrics failed'),
        ),
      );

      final result = await service.collectSnapshot();

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<domain.ConnectionFailure>());
      verifyNever(() => mockService.getPreparedStatementsMetrics());
    });
  });
}
