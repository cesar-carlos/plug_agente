import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/domain/repositories/i_sql_execution_idle_wait_port.dart';
import 'package:result_dart/result_dart.dart';

final class SqlExecutionIdleWaitAdapter implements ISqlExecutionIdleWaitPort {
  const SqlExecutionIdleWaitAdapter(this._queue);

  final SqlExecutionQueue _queue;

  @override
  Future<Result<Unit>> waitForActiveWorkers({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final result = await _queue.waitForActiveWorkers(timeout: timeout);
    return result.map((_) => unit);
  }
}
