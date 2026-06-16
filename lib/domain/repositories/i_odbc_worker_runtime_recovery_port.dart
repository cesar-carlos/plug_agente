/// Invalidates ODBC runtime state after the native async worker recovers from a crash.
abstract interface class IOdbcWorkerRuntimeRecoveryPort {
  Future<void> recoverAfterNativeWorkerCrash();
}
