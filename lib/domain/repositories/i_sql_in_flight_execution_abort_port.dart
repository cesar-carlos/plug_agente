import 'package:result_dart/result_dart.dart';

/// Port for aborting in-flight ODBC work without direct FFI from the queue.
abstract interface class ISqlInFlightExecutionAbortPort {
  /// Requests native ODBC cancel for [requestId].
  ///
  /// Returns `Success(true)` when a registered handle was found and abort was
  /// requested; `Success(false)` when nothing is registered for [requestId] at
  /// call time.
  ///
  /// When [armIfMissing] is true and no handle is registered yet, implementations
  /// may arm a pending abort that fires when the handle is later registered
  /// (closes the queue-timeout-vs-start ghost-query race). Unknown cancel misses
  /// must leave [armIfMissing] false so a miss does not poison a later unrelated
  /// execution that reuses the same id.
  ///
  /// Returns [Failure] only for abort/FFI errors after a handle was found.
  Future<Result<bool>> abortInFlightExecution(
    String requestId, {
    bool armIfMissing = false,
  });
}
