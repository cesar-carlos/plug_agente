/// Reloads ODBC runtime singletons after persisted connection settings change.
abstract interface class IOdbcRuntimeReloader {
  Future<bool> reload();
}
