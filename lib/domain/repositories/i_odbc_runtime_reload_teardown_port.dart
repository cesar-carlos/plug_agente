/// Coordinates teardown steps before ODBC runtime reload without coupling
/// infrastructure to application services.
abstract interface class IOdbcRuntimeReloadTeardownPort {
  bool markAgentActionsDraining();

  void markAgentActionsReady();

  /// Disposes the action execution queue (fails pending, waits for running).
  ///
  /// Must run before [disposeSqlExecutionQueue] so in-flight actions do not hit
  /// a disposed SQL queue / pool during reload.
  Future<void> disposeActionExecutionQueue();

  Future<void> disposeSqlExecutionQueue();

  Future<void> drainStreamingSessionCache();

  Future<void> disconnectHubTransport();
}
