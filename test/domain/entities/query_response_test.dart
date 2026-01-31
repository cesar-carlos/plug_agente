import 'package:flutter_test/flutter_test.dart';

import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';

void main() {
  group('QueryRequest', () {
    final timestamp = DateTime(2024);

    group('equality', () {
      test('should be equal when ids are the same', () {
        // Arrange
        final request1 = QueryRequest(
          id: 'query-1',
          agentId: 'agent-1',
          query: 'SELECT * FROM users',
          timestamp: timestamp,
        );
        final request2 = QueryRequest(
          id: 'query-1',
          agentId: 'agent-2',
          query: 'SELECT * FROM products',
          timestamp: timestamp,
        );

        // Assert
        expect(request1, equals(request2));
        expect(request1.hashCode, equals(request2.hashCode));
      });

      test('should not be equal when ids are different', () {
        // Arrange
        final request1 = QueryRequest(
          id: 'query-1',
          agentId: 'agent-1',
          query: 'SELECT * FROM users',
          timestamp: timestamp,
        );
        final request2 = QueryRequest(
          id: 'query-2',
          agentId: 'agent-1',
          query: 'SELECT * FROM users',
          timestamp: timestamp,
        );

        // Assert
        expect(request1, isNot(equals(request2)));
      });

      test('should not be equal when comparing to different type', () {
        // Arrange
        final request = QueryRequest(
          id: 'query-1',
          agentId: 'agent-1',
          query: 'SELECT * FROM users',
          timestamp: timestamp,
        );

        // Assert
        expect(request, isNot(equals('query-1')));
        expect(request, isNot(equals(123)));
      });
    });

    group('named constructors', () {
      test('should create instance with default values', () {
        // Act
        final request = QueryRequest(
          id: 'query-1',
          agentId: 'agent-1',
          query: 'SELECT * FROM users',
          timestamp: timestamp,
        );

        // Assert
        expect(request.id, 'query-1');
        expect(request.agentId, 'agent-1');
        expect(request.query, 'SELECT * FROM users');
        expect(request.parameters, isNull);
      });

      test('should create instance with parameters', () {
        // Arrange
        final parameters = {'id': 1, 'name': 'John'};

        // Act
        final request = QueryRequest(
          id: 'query-1',
          agentId: 'agent-1',
          query: 'SELECT * FROM users WHERE id = :id',
          parameters: parameters,
          timestamp: timestamp,
        );

        // Assert
        expect(request.parameters, equals(parameters));
      });

      test('should have timestamp', () {
        // Arrange & Act
        final request = QueryRequest(
          id: 'query-1',
          agentId: 'agent-1',
          query: 'SELECT * FROM users',
          timestamp: timestamp,
        );

        // Assert
        expect(request.timestamp, equals(timestamp));
      });
    });
  });

  group('QueryResponse', () {
    final timestamp = DateTime(2024);

    group('equality', () {
      test('should be equal when ids are the same', () {
        // Arrange
        final response1 = QueryResponse(
          id: 'response-1',
          requestId: 'query-1',
          agentId: 'agent-1',
          data: [
            {'id': 1, 'name': 'John'},
          ],
          timestamp: timestamp,
        );
        final response2 = QueryResponse(
          id: 'response-1',
          requestId: 'query-2',
          agentId: 'agent-2',
          data: [
            {'id': 2, 'email': 'jane@example.com'},
          ],
          timestamp: timestamp,
        );

        // Assert
        expect(response1, equals(response2));
        expect(response1.hashCode, equals(response2.hashCode));
      });

      test('should not be equal when ids are different', () {
        // Arrange
        final response1 = QueryResponse(
          id: 'response-1',
          requestId: 'query-1',
          agentId: 'agent-1',
          data: [
            {'id': 1, 'name': 'John'},
          ],
          timestamp: timestamp,
        );
        final response2 = QueryResponse(
          id: 'response-2',
          requestId: 'query-1',
          agentId: 'agent-1',
          data: [
            {'id': 1, 'name': 'John'},
          ],
          timestamp: timestamp,
        );

        // Assert
        expect(response1, isNot(equals(response2)));
      });
    });

    group('properties', () {
      test('should return correct data', () {
        // Arrange
        final data = [
          {'id': 1, 'name': 'John'},
          {'id': 2, 'name': 'Jane'},
          {'id': 3, 'name': 'Bob'},
        ];

        final response = QueryResponse(
          id: 'response-1',
          requestId: 'query-1',
          agentId: 'agent-1',
          data: data,
          timestamp: timestamp,
        );

        // Assert
        expect(response.data, equals(data));
        expect(response.data.length, 3);
      });

      test('should handle affectedRows', () {
        // Arrange
        final response = QueryResponse(
          id: 'response-1',
          requestId: 'query-1',
          agentId: 'agent-1',
          data: [],
          affectedRows: 5,
          timestamp: timestamp,
        );

        // Assert
        expect(response.affectedRows, 5);
      });

      test('should have timestamp', () {
        // Arrange & Act
        final response = QueryResponse(
          id: 'response-1',
          requestId: 'query-1',
          agentId: 'agent-1',
          data: [],
          timestamp: timestamp,
        );

        // Assert
        expect(response.timestamp, equals(timestamp));
      });

      test('should handle error', () {
        // Arrange
        final response = QueryResponse(
          id: 'response-1',
          requestId: 'query-1',
          agentId: 'agent-1',
          data: [],
          timestamp: timestamp,
          error: 'Table not found',
        );

        // Assert
        expect(response.error, 'Table not found');
      });

      test('should handle columnMetadata', () {
        // Arrange
        final metadata = [
          {'name': 'id', 'type': 'INT'},
          {'name': 'name', 'type': 'VARCHAR'},
        ];

        final response = QueryResponse(
          id: 'response-1',
          requestId: 'query-1',
          agentId: 'agent-1',
          data: [],
          timestamp: timestamp,
          columnMetadata: metadata,
        );

        // Assert
        expect(response.columnMetadata, equals(metadata));
      });

      test('should handle null values correctly', () {
        // Arrange
        final response = QueryResponse(
          id: 'response-1',
          requestId: 'query-1',
          agentId: 'agent-1',
          data: [],
          timestamp: timestamp,
        );

        // Assert
        expect(response.affectedRows, isNull);
        expect(response.error, isNull);
        expect(response.columnMetadata, isNull);
      });
    });
  });
}
