import 'package:result_dart/result_dart.dart';

/// Waits for in-flight SQL queue workers without disposing the queue.
abstract interface class ISqlExecutionIdleWaitPort {
  Future<Result<Unit>> waitForActiveWorkers({
    Duration timeout = const Duration(seconds: 30),
  });
}
