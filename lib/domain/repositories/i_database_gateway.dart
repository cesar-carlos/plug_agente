import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:result_dart/result_dart.dart';

abstract class IDatabaseGateway {
  /// Drops any in-memory cached agent config so the next operation reloads from persistence.
  void invalidateConfigCache();

  Future<Result<bool>> testConnection(String connectionString);
  Future<Result<QueryResponse>> executeQuery(
    QueryRequest request, {
    Duration? timeout,
    String? database,
  });
  Future<Result<List<SqlCommandResult>>> executeBatch(
    String agentId,
    List<SqlCommand> commands, {
    String? database,
    SqlExecutionOptions options = const SqlExecutionOptions(),
    Duration? timeout,
  });
  Future<Result<int>> executeNonQuery(
    String query,
    Map<String, dynamic>? parameters, {
    Duration? timeout,
    String? database,
  });
}
