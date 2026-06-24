/// Supplies synchronous agent health status for transport piggyback (ADR 0011).
abstract interface class IAgentHealthStatusProvider {
  Map<String, Object?> getHealthStatus();
}
