import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

// Mocks
class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class MockAgentConfigRepository extends Mock
    implements IAgentConfigRepository {}

class MockUuid extends Mock implements Uuid {}

void main() {
  // Register fallback values for mocktail
  setUpAll(() {
    registerFallbackValue(
      QueryRequest(
        id: 'test-id',
        agentId: 'test-agent',
        query: 'test',
        timestamp: DateTime.now(),
      ),
    );
  });

  group('ExecutePlaygroundQuery Integration Tests', () {
    late ExecutePlaygroundQuery useCase;
    late MockDatabaseGateway mockDatabaseGateway;
    late MockAgentConfigRepository mockConfigRepository;
    late MockUuid mockUuid;

    setUp(() {
      mockDatabaseGateway = MockDatabaseGateway();
      mockConfigRepository = MockAgentConfigRepository();
      mockUuid = MockUuid();

      useCase = ExecutePlaygroundQuery(
        mockDatabaseGateway,
        mockConfigRepository,
        mockUuid,
      );

      // Setup default mock behaviors
      when(() => mockUuid.v4()).thenReturn('test-uuid-123');
    });

    test('should fail when query is empty', () async {
      // Act
      final result = await useCase.call('   ');

      // Assert
      expect(result.isError(), isTrue);
      result.fold(
        (success) => fail('Should have failed'),
        (failure) {
          expect(failure, isA<domain.ValidationFailure>());
          expect(failure.toString(), contains('não pode estar vazia'));
        },
      );
    });

    test('should fail when SQL validation rejects dangerous query', () async {
      // Act
      final result = await useCase.call('DROP TABLE users');

      // Assert
      expect(result.isError(), isTrue);
      result.fold(
        (success) => fail('Should have failed'),
        (failure) {
          expect(failure, isA<domain.ValidationFailure>());
          expect(failure.toString(), contains('SELECT/WITH'));
        },
      );
    });

    test('should fail when config is not found', () async {
      // Arrange
      const validQuery = 'SELECT * FROM users';
      when(() => mockConfigRepository.getCurrentConfig()).thenAnswer(
        (_) async => Failure(domain.NotFoundFailure('Config not found')),
      );

      // Act
      final result = await useCase.call(validQuery);

      // Assert
      expect(result.isError(), isTrue);
      result.fold(
        (success) => fail('Should have failed'),
        (failure) {
          expect(failure, isA<domain.ConfigurationFailure>());
          expect(failure.toString(), contains('Configuração não encontrada'));
        },
      );
    });

    test('should successfully execute valid query with config', () async {
      // Arrange
      const validQuery = 'SELECT * FROM users';
      final config = Config(
        id: 'config-1',
        agentId: 'agent-123',
        driverName: 'MySQL',
        odbcDriverName: 'ODBC Driver for MySQL',
        connectionString: 'DSN=Test',
        username: 'root',
        databaseName: 'testdb',
        host: 'localhost',
        port: 3306,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final expectedResponse = QueryResponse(
        id: 'response-1',
        requestId: 'test-uuid-123',
        agentId: 'agent-123',
        data: [
          {'id': 1, 'name': 'John'},
        ],
        timestamp: DateTime.now(),
      );

      when(
        () => mockConfigRepository.getCurrentConfig(),
      ).thenAnswer((_) async => Success(config));
      when(
        () => mockDatabaseGateway.executeQuery(any()),
      ).thenAnswer((_) async => Success(expectedResponse));

      // Act
      final result = await useCase.call(validQuery);

      // Assert
      expect(result.isSuccess(), isTrue);
      final response = result.getOrNull();
      expect(response, isNotNull);
      expect(response!.data.length, 1);
      expect(response.data.first['name'], 'John');
    });

    test('should propagate database gateway failure', () async {
      // Arrange
      const validQuery = 'SELECT * FROM users';
      final config = Config(
        id: 'config-1',
        agentId: 'agent-123',
        driverName: 'MySQL',
        odbcDriverName: 'ODBC Driver for MySQL',
        connectionString: 'DSN=Test',
        username: 'root',
        databaseName: 'testdb',
        host: 'localhost',
        port: 3306,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(
        () => mockConfigRepository.getCurrentConfig(),
      ).thenAnswer((_) async => Success(config));
      when(() => mockDatabaseGateway.executeQuery(any())).thenAnswer(
        (_) async => Failure(domain.QueryExecutionFailure('SQL error')),
      );

      // Act
      final result = await useCase.call(validQuery);

      // Assert
      expect(result.isError(), isTrue);
      result.fold(
        (success) => fail('Should have failed'),
        (failure) {
          expect(failure, isA<domain.QueryExecutionFailure>());
          expect(failure.toString(), contains('SQL error'));
        },
      );
    });

    test('should accept valid WITH (CTE) query', () async {
      // Arrange
      const validQuery = 'WITH cte AS (SELECT 1) SELECT * FROM cte';
      final config = Config(
        id: 'config-1',
        agentId: 'agent-123',
        driverName: 'MySQL',
        odbcDriverName: 'ODBC Driver for MySQL',
        connectionString: 'DSN=Test',
        username: 'root',
        databaseName: 'testdb',
        host: 'localhost',
        port: 3306,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final expectedResponse = QueryResponse(
        id: 'response-1',
        requestId: 'test-uuid-123',
        agentId: 'agent-123',
        data: [],
        timestamp: DateTime.now(),
      );

      when(
        () => mockConfigRepository.getCurrentConfig(),
      ).thenAnswer((_) async => Success(config));
      when(
        () => mockDatabaseGateway.executeQuery(any()),
      ).thenAnswer((_) async => Success(expectedResponse));

      // Act
      final result = await useCase.call(validQuery);

      // Assert
      expect(result.isSuccess(), isTrue);
    });

    test('should reject query with SQL injection pattern', () async {
      // Act
      final result = await useCase.call(
        'SELECT * FROM users -- DROP TABLE users',
      );

      // Assert
      expect(result.isError(), isTrue);
      result.fold(
        (success) => fail('Should have failed'),
        (failure) {
          expect(failure, isA<domain.ValidationFailure>());
        },
      );
    });

    test('should create QueryRequest with UUID from Uuid service', () async {
      // Arrange
      const validQuery = 'SELECT * FROM users';
      const expectedUuid = 'generated-uuid-456';
      final config = Config(
        id: 'config-1',
        agentId: 'agent-789',
        driverName: 'MySQL',
        odbcDriverName: 'ODBC Driver for MySQL',
        connectionString: 'DSN=Test',
        username: 'root',
        databaseName: 'testdb',
        host: 'localhost',
        port: 3306,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      when(() => mockUuid.v4()).thenReturn(expectedUuid);

      final expectedResponse = QueryResponse(
        id: 'response-1',
        requestId: expectedUuid,
        agentId: 'agent-789',
        data: [],
        timestamp: DateTime.now(),
      );

      when(
        () => mockConfigRepository.getCurrentConfig(),
      ).thenAnswer((_) async => Success(config));
      when(
        () => mockDatabaseGateway.executeQuery(any()),
      ).thenAnswer((_) async => Success(expectedResponse));

      // Act
      await useCase.call(validQuery);

      // Assert - verificar que a query foi criada com o UUID correto
      final captured = verify(
        () => mockDatabaseGateway.executeQuery(captureAny()),
      ).captured;
      expect(captured.length, 1);
      expect(captured.first, isA<QueryRequest>());

      final request = captured.first as QueryRequest;
      expect(request.id, expectedUuid);
    });

    test('should handle mixed case SELECT query', () async {
      // Arrange
      const validQuery = 'select * from users';
      final config = Config(
        id: 'config-1',
        agentId: 'agent-123',
        driverName: 'MySQL',
        odbcDriverName: 'ODBC Driver for MySQL',
        connectionString: 'DSN=Test',
        username: 'root',
        databaseName: 'testdb',
        host: 'localhost',
        port: 3306,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final expectedResponse = QueryResponse(
        id: 'response-1',
        requestId: 'test-uuid-123',
        agentId: 'agent-123',
        data: [],
        timestamp: DateTime.now(),
      );

      when(
        () => mockConfigRepository.getCurrentConfig(),
      ).thenAnswer((_) async => Success(config));
      when(
        () => mockDatabaseGateway.executeQuery(any()),
      ).thenAnswer((_) async => Success(expectedResponse));

      // Act
      final result = await useCase.call(validQuery);

      // Assert
      expect(result.isSuccess(), isTrue);
    });
  });
}
