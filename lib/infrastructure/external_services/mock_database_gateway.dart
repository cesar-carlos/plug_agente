import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class MockDatabaseGateway implements IDatabaseGateway {
  MockDatabaseGateway() : _uuid = const Uuid();
  final Uuid _uuid;

  @override
  Future<Result<bool>> testConnection(String connectionString) async {
    // Simulate connection test
    if (connectionString.contains('fail')) {
      return Failure(domain.ConnectionFailure('Connection test failed'));
    }

    return const Success(true);
  }

  @override
  Future<Result<QueryResponse>> executeQuery(QueryRequest request) async {
    // Simulate query execution
    if (request.query.toLowerCase().contains('error')) {
      final errorResponse = QueryResponse(
        id: _uuid.v4(),
        requestId: request.id,
        agentId: request.agentId,
        data: [],
        timestamp: DateTime.now(),
        error: 'Simulated query error',
      );

      return Success(errorResponse);
    }

    // Mock data for SELECT queries
    var mockData = <Map<String, dynamic>>[];

    if (request.query.toLowerCase().contains('select')) {
      mockData = [
        {'id': 1, 'name': 'Test User 1', 'email': 'test1@example.com'},
        {'id': 2, 'name': 'Test User 2', 'email': 'test2@example.com'},
        {'id': 3, 'name': 'Test User 3', 'email': 'test3@example.com'},
      ];
    }

    final response = QueryResponse(
      id: _uuid.v4(),
      requestId: request.id,
      agentId: request.agentId,
      data: mockData,
      affectedRows: mockData.length,
      timestamp: DateTime.now(),
    );

    return Success(response);
  }

  @override
  Future<Result<int>> executeNonQuery(
    String query,
    Map<String, dynamic>? parameters,
  ) async {
    // Simulate non-query execution
    if (query.toLowerCase().contains('error')) {
      return Failure(
        domain.QueryExecutionFailure('Failed to execute non-query'),
      );
    }

    // Mock affected rows for INSERT/UPDATE/DELETE
    var affectedRows = 0;
    if (query.toLowerCase().contains('insert')) {
      affectedRows = 1;
    } else if (query.toLowerCase().contains('update')) {
      affectedRows = 1;
    } else if (query.toLowerCase().contains('delete')) {
      affectedRows = 1;
    }

    return Success(affectedRows);
  }
}
