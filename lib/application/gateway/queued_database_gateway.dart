import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:result_dart/result_dart.dart';

/// Wraps a database gateway with a bounded SQL execution queue.
///
/// Routes `executeQuery` and `executeBatch` through the queue to prevent
/// pool overload. Non-SQL operations bypass the queue.
class QueuedDatabaseGateway implements IDatabaseGateway {
  QueuedDatabaseGateway({
    required IDatabaseGateway delegate,
    required SqlExecutionQueue queue,
  })  : _delegate = delegate,
        _queue = queue;

  final IDatabaseGateway _delegate;
  final SqlExecutionQueue _queue;

  /// Queue size for monitoring.
  int get queueSize => _queue.queueSize;

  /// Active workers for monitoring.
  int get activeWorkers => _queue.activeWorkers;

  @override
  Future<Result<bool>> testConnection(String connectionString) {
    // Bypass queue for connection tests
    return _delegate.testConnection(connectionString);
  }

  @override
  Future<Result<QueryResponse>> executeQuery(
    QueryRequest request, {
    Duration? timeout,
    String? database,
  }) {
    // Route through queue with requestId for tracking
    return _queue.submit(
      () => _delegate.executeQuery(
        request,
        timeout: timeout,
        database: database,
      ),
      requestId: request.id,
    );
  }

  @override
  Future<Result<List<SqlCommandResult>>> executeBatch(
    String agentId,
    List<SqlCommand> commands, {
    String? database,
    SqlExecutionOptions options = const SqlExecutionOptions(),
    Duration? timeout,
    String? sourceRpcRequestId,
  }) {
    // Route through queue (no requestId for batch)
    return _queue.submit(
      () => _delegate.executeBatch(
        agentId,
        commands,
        database: database,
        options: options,
        timeout: timeout,
        sourceRpcRequestId: sourceRpcRequestId,
      ),
    );
  }

  @override
  Future<Result<int>> executeNonQuery(
    String query,
    Map<String, dynamic>? parameters, {
    Duration? timeout,
    String? database,
  }) {
    // Route through queue (non-query SQL still needs queueing)
    return _queue.submit(
      () => _delegate.executeNonQuery(
        query,
        parameters,
        timeout: timeout,
        database: database,
      ),
    );
  }

  /// Disposes the SQL execution queue.
  ///
  /// Should be called during app shutdown to properly clean up pending requests.
  void dispose() {
    _queue.dispose();
  }
}
