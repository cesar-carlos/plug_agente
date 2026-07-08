import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/validation/query_validation_messages.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_query_config_source.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

// Mocks
class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class MockQueryConfigSource extends Mock implements IQueryConfigSource {}

class MockUuid extends Mock implements Uuid {}

const _materializedPlaygroundQuery = 'SELECT * FROM users ORDER BY id';
const _materializedPlaygroundPagination = QueryPaginationRequest(page: 1, pageSize: 50);

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
    late MockQueryConfigSource mockQueryConfigSource;
    late MockUuid mockUuid;

    setUp(() {
      mockDatabaseGateway = MockDatabaseGateway();
      mockQueryConfigSource = MockQueryConfigSource();
      mockUuid = MockUuid();

      useCase = ExecutePlaygroundQuery(
        mockDatabaseGateway,
        mockQueryConfigSource,
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
          expect(
            failure.toString(),
            contains(QueryValidationMessages.queryCannotBeEmpty),
          );
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

    test('should resolve explicit config id via query config source', () async {
      const validQuery = _materializedPlaygroundQuery;
      const explicitConfigId = 'config-explicit';
      final config = Config(
        id: explicitConfigId,
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
        () => mockQueryConfigSource.resolveConfigForQuery(explicitConfigId),
      ).thenAnswer((_) async => Success(config));
      when(
        () => mockDatabaseGateway.executeQuery(
          any(),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer(
        (_) async => Success(
          QueryResponse(
            id: 'response-1',
            requestId: 'test-uuid-123',
            agentId: 'agent-123',
            data: const [],
            timestamp: DateTime.now(),
          ),
        ),
      );

      final result = await useCase.call(
        validQuery,
        configId: explicitConfigId,
        pagination: _materializedPlaygroundPagination,
      );

      expect(result.isSuccess(), isTrue);
      verify(
        () => mockQueryConfigSource.resolveConfigForQuery(explicitConfigId),
      ).called(1);
    });

    test('should fail when config is not found', () async {
      // Arrange
      const validQuery = _materializedPlaygroundQuery;
      when(() => mockQueryConfigSource.resolveConfigForQuery(any())).thenAnswer(
        (_) async => Failure(domain.NotFoundFailure('Config not found')),
      );

      // Act
      final result = await useCase.call(
        validQuery,
        pagination: _materializedPlaygroundPagination,
      );

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
      const validQuery = _materializedPlaygroundQuery;
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
        () => mockQueryConfigSource.resolveConfigForQuery(any()),
      ).thenAnswer((_) async => Success(config));
      when(
        () => mockDatabaseGateway.executeQuery(
          any(),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => Success(expectedResponse));

      // Act
      final result = await useCase.call(
        validQuery,
        pagination: _materializedPlaygroundPagination,
      );

      // Assert
      expect(result.isSuccess(), isTrue);
      final response = result.getOrNull();
      expect(response, isNotNull);
      expect(response!.data.length, 1);
      expect(response.data.first['name'], 'John');
      verify(
        () => mockDatabaseGateway.executeQuery(
          any(),
          timeout: ConnectionConstants.defaultQueryTimeout,
        ),
      ).called(1);
    });

    test('should propagate database gateway failure', () async {
      // Arrange
      const validQuery = _materializedPlaygroundQuery;
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
        () => mockQueryConfigSource.resolveConfigForQuery(any()),
      ).thenAnswer((_) async => Success(config));
      when(
        () => mockDatabaseGateway.executeQuery(
          any(),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => Failure(domain.QueryExecutionFailure('SQL error')));

      // Act
      final result = await useCase.call(
        validQuery,
        pagination: _materializedPlaygroundPagination,
      );

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
      const validQuery = 'WITH cte AS (SELECT 1 AS id) SELECT id FROM cte ORDER BY id';
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
        () => mockQueryConfigSource.resolveConfigForQuery(any()),
      ).thenAnswer((_) async => Success(config));
      when(
        () => mockDatabaseGateway.executeQuery(
          any(),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => Success(expectedResponse));

      // Act
      final result = await useCase.call(
        validQuery,
        pagination: _materializedPlaygroundPagination,
      );

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
      const validQuery = _materializedPlaygroundQuery;
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
        () => mockQueryConfigSource.resolveConfigForQuery(any()),
      ).thenAnswer((_) async => Success(config));
      when(
        () => mockDatabaseGateway.executeQuery(
          any(),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => Success(expectedResponse));

      // Act
      await useCase.call(
        validQuery,
        pagination: _materializedPlaygroundPagination,
      );

      // Assert - verificar que a query foi criada com o UUID correto
      final captured = verify(
        () => mockDatabaseGateway.executeQuery(
          captureAny(),
          timeout: ConnectionConstants.defaultQueryTimeout,
        ),
      ).captured;
      expect(captured.length, 1);
      expect(captured.first, isA<QueryRequest>());

      final request = captured.first as QueryRequest;
      expect(request.id, expectedUuid);
    });

    test('should handle mixed case SELECT query', () async {
      // Arrange
      const validQuery = 'select * from users order by id';
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
        () => mockQueryConfigSource.resolveConfigForQuery(any()),
      ).thenAnswer((_) async => Success(config));
      when(
        () => mockDatabaseGateway.executeQuery(
          any(),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => Success(expectedResponse));

      // Act
      final result = await useCase.call(
        validQuery,
        pagination: _materializedPlaygroundPagination,
      );

      // Assert
      expect(result.isSuccess(), isTrue);
    });

    test(
      'should enrich pagination metadata when query declares ORDER BY',
      () async {
        const validQuery = 'SELECT * FROM users ORDER BY id';
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
          data: const [],
          timestamp: DateTime.now(),
        );

        when(
          () => mockQueryConfigSource.resolveConfigForQuery(any()),
        ).thenAnswer((_) async => Success(config));
        when(
          () => mockDatabaseGateway.executeQuery(
            any(),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => Success(expectedResponse));

        await useCase.call(
          validQuery,
          pagination: const QueryPaginationRequest(page: 1, pageSize: 50),
        );

        final captured =
            verify(
                  () => mockDatabaseGateway.executeQuery(
                    captureAny(),
                    timeout: ConnectionConstants.defaultQueryTimeout,
                  ),
                ).captured.single
                as QueryRequest;

        expect(captured.pagination, isNotNull);
        expect(captured.pagination!.orderBy, hasLength(1));
        expect(captured.pagination!.orderBy.single.expression, 'id');
        expect(captured.pagination!.queryHash, isNotNull);
      },
    );

    test(
      'should execute materialized playground query without ORDER BY when within materialized cap',
      () async {
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
          data: const [
            {'id': 1, 'name': 'John'},
          ],
          timestamp: DateTime.now(),
        );

        when(
          () => mockQueryConfigSource.resolveConfigForQuery(any()),
        ).thenAnswer((_) async => Success(config));
        when(
          () => mockDatabaseGateway.executeQuery(
            any(),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => Success(expectedResponse));

        final result = await useCase.call(
          validQuery,
          pagination: const QueryPaginationRequest(page: 1, pageSize: 50),
        );

        expect(result.isSuccess(), isTrue);
        verify(
          () => mockDatabaseGateway.executeQuery(
            any(),
            timeout: ConnectionConstants.defaultQueryTimeout,
          ),
        ).called(1);
      },
    );

    test(
      'should skip managed pagination when query declares SELECT TOP row limit',
      () async {
        const topQuery = 'SELECT TOP 1 Nome FROM Cliente ORDER BY CodCliente';
        final config = Config(
          id: 'config-1',
          agentId: 'agent-123',
          driverName: 'SQL Anywhere',
          odbcDriverName: 'SQL Anywhere',
          connectionString: 'DSN=Test',
          username: 'dba',
          databaseName: 'testdb',
          host: 'localhost',
          port: 2638,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final expectedResponse = QueryResponse(
          id: 'response-1',
          requestId: 'test-uuid-123',
          agentId: 'agent-123',
          data: const [
            {'Nome': 'Acme'},
          ],
          timestamp: DateTime.now(),
        );

        when(
          () => mockQueryConfigSource.resolveConfigForQuery(any()),
        ).thenAnswer((_) async => Success(config));
        when(
          () => mockDatabaseGateway.executeQuery(
            any(),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => Success(expectedResponse));

        final result = await useCase.call(
          topQuery,
          pagination: const QueryPaginationRequest(page: 1, pageSize: 50),
        );

        expect(result.isSuccess(), isTrue);
        final captured =
            verify(
                  () => mockDatabaseGateway.executeQuery(
                    captureAny(),
                    timeout: ConnectionConstants.defaultQueryTimeout,
                  ),
                ).captured.single
                as QueryRequest;

        expect(captured.pagination, isNull);
        expect(captured.query, topQuery);
      },
    );

    test(
      'should skip managed pagination when WITH query declares SELECT TOP row limit',
      () async {
        const topQuery =
            'WITH cte AS (SELECT CodCliente FROM Cliente) '
            'SELECT TOP 1 Nome FROM cte ORDER BY CodCliente';
        final config = Config(
          id: 'config-1',
          agentId: 'agent-123',
          driverName: 'SQL Anywhere',
          odbcDriverName: 'SQL Anywhere',
          connectionString: 'DSN=Test',
          username: 'dba',
          databaseName: 'testdb',
          host: 'localhost',
          port: 2638,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final expectedResponse = QueryResponse(
          id: 'response-1',
          requestId: 'test-uuid-123',
          agentId: 'agent-123',
          data: const [
            {'Nome': 'Acme'},
          ],
          timestamp: DateTime.now(),
        );

        when(
          () => mockQueryConfigSource.resolveConfigForQuery(any()),
        ).thenAnswer((_) async => Success(config));
        when(
          () => mockDatabaseGateway.executeQuery(
            any(),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => Success(expectedResponse));

        final result = await useCase.call(
          topQuery,
          pagination: const QueryPaginationRequest(page: 1, pageSize: 50),
        );

        expect(result.isSuccess(), isTrue);
        final captured =
            verify(
                  () => mockDatabaseGateway.executeQuery(
                    captureAny(),
                    timeout: ConnectionConstants.defaultQueryTimeout,
                  ),
                ).captured.single
                as QueryRequest;

        expect(captured.pagination, isNull);
        expect(captured.query, topQuery);
      },
    );

    test(
      'should disable pagination when query expects multiple result sets',
      () async {
        const validQuery = 'SELECT 1; SELECT 2;';
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
          data: const [],
          timestamp: DateTime.now(),
        );

        when(
          () => mockQueryConfigSource.resolveConfigForQuery(any()),
        ).thenAnswer((_) async => Success(config));
        when(
          () => mockDatabaseGateway.executeQuery(
            any(),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => Success(expectedResponse));

        await useCase.call(
          validQuery,
          pagination: const QueryPaginationRequest(page: 1, pageSize: 50),
        );

        final captured =
            verify(
                  () => mockDatabaseGateway.executeQuery(
                    captureAny(),
                    timeout: ConnectionConstants.defaultQueryTimeout,
                  ),
                ).captured.single
                as QueryRequest;

        expect(captured.expectMultipleResults, isTrue);
        expect(captured.pagination, isNull);
      },
    );
  });
}
