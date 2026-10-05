import 'package:result_dart/result_dart.dart';

/// Lifecycle barrier for known connection-discard tasks, outside SQL execution.
abstract interface class IOdbcPendingDiscardsWaitPort {
  Future<Result<void>> waitForPendingDiscards({required Duration timeout});
}
