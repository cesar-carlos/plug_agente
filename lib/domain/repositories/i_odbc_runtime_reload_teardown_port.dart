/// Coordinates teardown steps before ODBC runtime reload without coupling
/// infrastructure to application services.
abstract interface class IOdbcRuntimeReloadTeardownPort {
  bool markAgentActionsDraining();

  void markAgentActionsReady();

  Future<void> disposeSqlExecutionQueue();

  Future<void> drainStreamingSessionCache();

  Future<void> disconnectHubTransport();
}
