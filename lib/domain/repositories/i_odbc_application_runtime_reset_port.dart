/// Resets application-layer lazy singletons during an ODBC runtime reload.
abstract interface class IOdbcApplicationRuntimeResetPort {
  Future<void> resetForOdbcRuntimeReload();
}
