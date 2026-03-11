import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/compression_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/handle_query_request.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:result_dart/result_dart.dart';

class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class MockTransportClient extends Mock implements ITransportClient {}

class MockQueryNormalizerService extends Mock implements QueryNormalizerService {}

class MockCompressionService extends Mock implements CompressionService {}

void main() {
  group('HandleQueryRequest', () {
    late MockDatabaseGateway mockDatabaseGateway;
    late MockTransportClient mockTransportClient;
    late MockQueryNormalizerService mockNormalizerService;
    late MockCompressionService mockCompressionService;
    late HandleQueryRequest useCase;

    setUpAll(() {
      registerFallbackValue(
        QueryRequest(
          id: 'request-fallback',
          agentId: 'agent-fallback',
          query: 'SELECT 1',
          timestamp: DateTime(2026),
        ),
      );
      registerFallbackValue(
        QueryResponse(
          id: 'response-id',
          requestId: 'request-id',
          agentId: 'agent-id',
          data: const [],
          timestamp: DateTime(2026),
        ),
      );
    });

    setUp(() {
      mockDatabaseGateway = MockDatabaseGateway();
      mockTransportClient = MockTransportClient();
      mockNormalizerService = MockQueryNormalizerService();
      mockCompressionService = MockCompressionService();
      useCase = HandleQueryRequest(
        mockDatabaseGateway,
        mockTransportClient,
        mockNormalizerService,
        mockCompressionService,
      );
    });

    test('should reject invalid SQL and send error response', () async {
      final request = QueryRequest(
        id: 'request-1',
        agentId: 'agent-1',
        query: 'DROP TABLE users',
        timestamp: DateTime.now(),
      );

      when(
        () => mockTransportClient.sendResponse(any()),
      ).thenAnswer((_) async => const Success(unit));

      final result = await useCase(request);

      expect(result.isSuccess(), isTrue);
      verifyNever(() => mockDatabaseGateway.executeQuery(any()));

      final captured =
          verify(() => mockTransportClient.sendResponse(captureAny()))
              .captured
              .single as QueryResponse;
      expect(captured.error, isNotNull);
      expect(captured.error, contains('SELECT/WITH'));
    });

    test('should send error response when gateway fails', () async {
      final request = QueryRequest(
        id: 'request-2',
        agentId: 'agent-2',
        query: 'SELECT * FROM users',
        timestamp: DateTime.now(),
      );

      when(() => mockDatabaseGateway.executeQuery(any())).thenAnswer(
        (_) async => Failure(domain.QueryExecutionFailure('database down')),
      );
      when(
        () => mockTransportClient.sendResponse(any()),
      ).thenAnswer((_) async => const Success(unit));

      final result = await useCase(request);

      expect(result.isSuccess(), isTrue);
      final captured =
          verify(() => mockTransportClient.sendResponse(captureAny()))
              .captured
              .single as QueryResponse;
      expect(captured.error, contains('database down'));
    });
  });
}
