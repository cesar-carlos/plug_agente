import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/compression_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/handle_query_request.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:result_dart/result_dart.dart';

class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class MockTransportClient extends Mock implements ITransportClient {}

class MockQueryNormalizerService extends Mock
    implements QueryNormalizerService {}

class MockCompressionService extends Mock implements CompressionService {}

class MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

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

    late MockAuthorizeSqlOperation mockAuthorize;
    late MockFeatureFlags mockFeatureFlags;

    setUp(() {
      mockDatabaseGateway = MockDatabaseGateway();
      mockTransportClient = MockTransportClient();
      mockNormalizerService = MockQueryNormalizerService();
      mockCompressionService = MockCompressionService();
      mockAuthorize = MockAuthorizeSqlOperation();
      mockFeatureFlags = MockFeatureFlags();
      when(
        () => mockFeatureFlags.enableClientTokenAuthorization,
      ).thenReturn(false);

      useCase = HandleQueryRequest(
        mockDatabaseGateway,
        mockTransportClient,
        mockNormalizerService,
        mockCompressionService,
        mockAuthorize,
        mockFeatureFlags,
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
          verify(
                () => mockTransportClient.sendResponse(captureAny()),
              ).captured.single
              as QueryResponse;
      expect(captured.error, isNotNull);
      expect(captured.error, contains('Unsupported'));
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
          verify(
                () => mockTransportClient.sendResponse(captureAny()),
              ).captured.single
              as QueryResponse;
      expect(captured.error, contains('database down'));
    });

    test('should not expose failure context in error response', () async {
      final request = QueryRequest(
        id: 'request-3',
        agentId: 'agent-3',
        query: 'SELECT * FROM users',
        timestamp: DateTime.now(),
      );
      final failure = domain.QueryExecutionFailure.withContext(
        message: 'database down',
        cause: Exception('socket timeout'),
        context: {'host': 'db.internal', 'retry': 2},
      );

      when(
        () => mockDatabaseGateway.executeQuery(any()),
      ).thenAnswer((_) async => Failure(failure));
      when(
        () => mockTransportClient.sendResponse(any()),
      ).thenAnswer((_) async => const Success(unit));

      final result = await useCase(request);

      expect(result.isSuccess(), isTrue);
      final captured =
          verify(
                () => mockTransportClient.sendResponse(captureAny()),
              ).captured.single
              as QueryResponse;
      expect(captured.error, equals('database down'));
      expect(captured.error, isNot(contains('Context:')));
      expect(captured.error, isNot(contains('Caused by:')));
    });

    test(
      'should return contextual failure when request handling throws',
      () async {
        final request = QueryRequest(
          id: 'request-4',
          agentId: 'agent-4',
          query: 'SELECT * FROM users',
          timestamp: DateTime.now(),
        );
        final exception = Exception('unexpected crash');

        when(
          () => mockDatabaseGateway.executeQuery(any()),
        ).thenThrow(exception);

        final result = await useCase(request);
        final failure =
            result.exceptionOrNull()! as domain.QueryExecutionFailure;

        expect(result.isError(), isTrue);
        expect(failure.message, 'Failed to handle query request');
        expect(failure.cause, exception);
        expect(failure.context, containsPair('requestId', 'request-4'));
        expect(failure.context, containsPair('agentId', 'agent-4'));
        verifyNever(() => mockTransportClient.sendResponse(any()));
      },
    );
  });
}
