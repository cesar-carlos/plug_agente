/// Presentation binds a live hub connection lifecycle sink so global shutdown
/// can cancel hub recovery timers before tearing down transport.
abstract interface class IHubConnectionShutdownPort {
  Future<void> disconnectForShutdown();
}
