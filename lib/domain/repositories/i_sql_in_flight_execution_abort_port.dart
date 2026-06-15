import 'package:result_dart/result_dart.dart';

/// Port for aborting in-flight ODBC work without direct FFI from the queue.
abstract interface class ISqlInFlightExecutionAbortPort {
  /// Best-effort native ODBC cancel for [requestId]. No-op when nothing is registered.
  Future<Result<void>> abortInFlightExecution(String requestId);
}
