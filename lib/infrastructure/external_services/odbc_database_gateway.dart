import 'package:result_dart/result_dart.dart';
import 'package:dart_odbc/dart_odbc.dart';
import '../../domain/entities/query_request.dart';
import '../../domain/entities/query_response.dart';
import '../../domain/repositories/i_database_gateway.dart';
import '../../domain/repositories/i_agent_config_repository.dart';
import '../../domain/errors/failures.dart' as domain;
import 'package:uuid/uuid.dart';

class OdbcDatabaseGateway implements IDatabaseGateway {
  final Uuid _uuid;
  final IAgentConfigRepository _configRepository;

  OdbcDatabaseGateway(this._configRepository) : _uuid = const Uuid();

  Future<Result<DartOdbc>> _connect(String connectionString) async {
    try {
      final odbc = DartOdbc();
      await odbc.connectWithConnectionString(connectionString);
      return Success(odbc);
    } catch (e) {
      return Failure(domain.ConnectionFailure('Failed to connect: $e'));
    }
  }

  Future<Result<void>> _disconnect(DartOdbc odbc) async {
    try {
      await odbc.disconnect();
      return Success<Object, Exception>(Object());
    } catch (e) {
      return Failure(domain.ConnectionFailure('Failed to disconnect: $e'));
    }
  }

  Future<Result<List<Map<String, dynamic>>>> _executeQuery(
    DartOdbc odbc,
    String query,
    List<dynamic>? params,
  ) async {
    try {
      final result = params != null && params.isNotEmpty
          ? await odbc.execute(query, params: params)
          : await odbc.execute(query);
      return Success(List<Map<String, dynamic>>.from(result));
    } catch (e) {
      return Failure(
        domain.QueryExecutionFailure('Failed to execute query: $e'),
      );
    }
  }

  @override
  Future<Result<bool>> testConnection(String connectionString) async {
    final connectResult = await _connect(connectionString);

    return await connectResult.fold((odbc) async {
      final disconnectResult = await _disconnect(odbc);
      return disconnectResult.fold((_) => Success(true), (failure) {
        final failureMessage = failure is domain.Failure
            ? failure.message
            : failure.toString();
        return Failure(
          domain.ConnectionFailure(
            'Connection test succeeded but disconnect failed: $failureMessage',
          ),
        );
      });
    }, (failure) => Failure(failure));
  }

  @override
  Future<Result<QueryResponse>> executeQuery(QueryRequest request) async {
    final configResult = await _configRepository.getCurrentConfig();

    return await configResult.fold(
      (config) async {
        final connectResult = await _connect(config.connectionString);

        return await connectResult.fold(
          (odbc) async {
            final params = request.parameters?.values.toList();
            final executeResult = await _executeQuery(
              odbc,
              request.query,
              params,
            );

            await _disconnect(odbc);

            return executeResult.fold(
              (data) {
                final response = QueryResponse(
                  id: _uuid.v4(),
                  requestId: request.id,
                  agentId: request.agentId,
                  data: data,
                  affectedRows: data.length,
                  timestamp: DateTime.now(),
                );
                return Success(response);
              },
              (failure) {
                final failureMessage = failure is domain.Failure
                    ? failure.message
                    : failure.toString();
                final errorResponse = QueryResponse(
                  id: _uuid.v4(),
                  requestId: request.id,
                  agentId: request.agentId,
                  data: [],
                  timestamp: DateTime.now(),
                  error: failureMessage,
                );
                return Success(errorResponse);
              },
            );
          },
          (failure) async {
            final failureMessage = failure is domain.Failure
                ? failure.message
                : failure.toString();
            final errorResponse = QueryResponse(
              id: _uuid.v4(),
              requestId: request.id,
              agentId: request.agentId,
              data: [],
              timestamp: DateTime.now(),
              error: failureMessage,
            );
            return Success(errorResponse);
          },
        );
      },
      (failure) async {
        final failureMessage = failure is domain.Failure
            ? failure.message
            : failure.toString();
        final errorResponse = QueryResponse(
          id: _uuid.v4(),
          requestId: request.id,
          agentId: request.agentId,
          data: [],
          timestamp: DateTime.now(),
          error: failureMessage,
        );
        return Success(errorResponse);
      },
    );
  }

  @override
  Future<Result<int>> executeNonQuery(
    String query,
    Map<String, dynamic>? parameters,
  ) async {
    final configResult = await _configRepository.getCurrentConfig();

    return await configResult.fold(
      (config) async {
        final connectResult = await _connect(config.connectionString);

        return await connectResult.fold((odbc) async {
          final params = parameters?.values.toList();
          final executeResult = await _executeQuery(odbc, query, params);

          await _disconnect(odbc);

          return executeResult.fold(
            (_) =>
                Success(0), // dart_odbc doesn't return affected rows directly
            (failure) => Failure(failure),
          );
        }, (failure) => Failure(failure));
      },
      (failure) async {
        final failureMessage = failure is domain.Failure
            ? failure.message
            : failure.toString();
        return Failure(
          domain.QueryExecutionFailure('Failed to get config: $failureMessage'),
        );
      },
    );
  }
}
