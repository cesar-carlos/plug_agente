/// Teardown hooks for infrastructure resources during application shutdown.
abstract interface class IAppInfrastructureShutdownPort {
  Future<void> closeLocalDatabase();

  void disposeMetricsCollectors();

  Future<void> disposeOdbcEventBridge();
}
