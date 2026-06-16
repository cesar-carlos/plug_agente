import 'package:plug_agente/application/gateway/odbc_connection_test_limiter.dart';
import 'package:plug_agente/application/gateway/sql_execution_kind_classifier.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
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
    SqlExecutionKindClassifier? queryClassifier,
    OdbcConnectionTestLimiter? connectionTestLimiter,
  }) : _delegate = delegate,
       _queue = queue,
       _queryClassifier = queryClassifier ?? SqlExecutionKindClassifier(),
       _connectionTestLimiter = connectionTestLimiter ?? OdbcConnectionTestLimiter();

  final IDatabaseGateway _delegate;
  final SqlExecutionQueue _queue;
  final SqlExecutionKindClassifier _queryClassifier;
  final OdbcConnectionTestLimiter _connectionTestLimiter;

  /// Inner gateway wrapped by the SQL execution queue.
  IDatabaseGateway get delegate => _delegate;

  /// Queue size for monitoring.
  int get queueSize => _queue.queueSize;

  /// Active workers for monitoring.
  int get activeWorkers => _queue.activeWorkers;

  int get maxQueueSize => _queue.maxQueueSize;

  int get maxWorkers => _queue.maxConcurrentWorkers;

  int get activeBatchWorkers => _queue.activeBatchWorkers;

  int get maxBatchWorkers => _queue.maxConcurrentBatchWorkers;

  int get activeLongQueryWorkers => _queue.activeLongQueryWorkers;

  int get maxLongQueryWorkers => _queue.maxConcurrentLongQueryWorkers;

  int get activeStreamingWorkers => _queue.activeStreamingWorkers;

  int get maxStreamingWorkers => _queue.maxConcurrentStreamingWorkers;

  int get activeNonQueryWorkers => _queue.activeNonQueryWorkers;

  int get maxNonQueryWorkers => _queue.maxConcurrentNonQueryWorkers;

  Duration get enqueueTimeout => _queue.defaultEnqueueTimeout;

  @override
  Future<Result<bool>> testConnection(String connectionString) {
    return _connectionTestLimiter.run(() => _delegate.testConnection(connectionString));
  }

  @override
  Future<Result<QueryResponse>> executeQuery(
    QueryRequest request, {
    Duration? timeout,
    String? database,
    CancellationToken? cancellationToken,
  }) {
    final lifecycleToken = cancellationToken ?? CancellationToken();
    return _queue.submit(
      () => _delegate.executeQuery(
        request,
        timeout: timeout,
        database: database,
        cancellationToken: lifecycleToken,
      ),
      requestId: request.id,
      kind: _queryClassifier.classify(request, timeout),
      cooperativeCancellationToken: lifecycleToken,
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
    CancellationToken? cancellationToken,
  }) {
    final lifecycleToken = cancellationToken ?? CancellationToken();
    final slotWeight = _batchSlotWeightFor(commands.length);
    return _queue.submit(
      () => _delegate.executeBatch(
        agentId,
        commands,
        database: database,
        options: options,
        timeout: timeout,
        sourceRpcRequestId: sourceRpcRequestId,
        cancellationToken: lifecycleToken,
      ),
      requestId: sourceRpcRequestId,
      kind: SqlExecutionKind.batch,
      cooperativeCancellationToken: lifecycleToken,
      slotWeight: slotWeight,
    );
  }

  @override
  Future<Result<int>> executeNonQuery(
    String query,
    Map<String, dynamic>? parameters, {
    Duration? timeout,
    String? database,
    CancellationToken? cancellationToken,
    String? sourceRpcRequestId,
  }) {
    final lifecycleToken = cancellationToken ?? CancellationToken();
    return _queue.submit(
      () => _delegate.executeNonQuery(
        query,
        parameters,
        timeout: timeout,
        database: database,
        cancellationToken: lifecycleToken,
        sourceRpcRequestId: sourceRpcRequestId,
      ),
      requestId: sourceRpcRequestId,
      kind: SqlExecutionKind.nonQuery,
      cooperativeCancellationToken: lifecycleToken,
    );
  }

  @override
  Future<Result<int>> executeBulkInsert(
    BulkInsertRequest request, {
    Duration? timeout,
    String? database,
    CancellationToken? cancellationToken,
    String? sourceRpcRequestId,
  }) {
    final lifecycleToken = cancellationToken ?? CancellationToken();
    final slotWeight = _batchSlotWeightFor(request.rowCount);
    return _queue.submit(
      () => _delegate.executeBulkInsert(
        request,
        timeout: timeout,
        database: database,
        cancellationToken: lifecycleToken,
        sourceRpcRequestId: sourceRpcRequestId,
      ),
      requestId: sourceRpcRequestId,
      kind: SqlExecutionKind.batch,
      cooperativeCancellationToken: lifecycleToken,
      slotWeight: slotWeight,
    );
  }

  int _batchSlotWeightFor(int commandOrRowCount) {
    if (commandOrRowCount <= 1) {
      return 1;
    }
    return commandOrRowCount.clamp(2, maxBatchWorkers);
  }

  /// Disposes the SQL execution queue.
  ///
  /// Should be called during app shutdown to properly clean up pending requests.
  void dispose() {
    _queue.dispose();
  }

  /// Disposes the queue and waits up to [timeout] for in-flight workers to
  /// finish so ODBC connections are released before shutdown completes.
  Future<Result<void>> disposeGracefully({
    Duration timeout = const Duration(seconds: 30),
  }) {
    return _queue.disposeGracefully(timeout: timeout);
  }
}
