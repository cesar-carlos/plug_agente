import 'package:result_dart/result_dart.dart';

/// Completion here means native resources are released, not business success.
/// Calls are idempotent: repeated observers share the same run and cleanup.
abstract interface class IActionIoSessionControl {
  Future<Result<Unit>> runAndDrain();
  Future<Result<Unit>> stopAndDrain();
}
