import 'package:result_dart/result_dart.dart';

/// Port for aborting in-flight ODBC work without direct FFI from the queue.
abstract interface class ISqlInFlightExecutionAbortPort {
  /// Requests native ODBC cancel for [requestId].
  ///
  /// Returns `Success(true)` when a registered handle was found and abort was
  /// requested; `Success(false)` when nothing is registered for [requestId].
  /// Returns [Failure] only for abort/FFI errors after a handle was found.
  Future<Result<bool>> abortInFlightExecution(String requestId);
}
