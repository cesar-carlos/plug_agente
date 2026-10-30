import 'package:result_dart/result_dart.dart';

/// Identifies the authoritative execution store, not caller authorization.
abstract interface class IActionIoExecutionOwnership {
  Future<Result<bool>> ownsExecution(String executionId);
}
