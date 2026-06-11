import 'package:plug_agente/application/gateway/queued_database_gateway.dart';

/// Derives an overall status string from the available pool/queue diagnostics.
///
/// - 'degraded': native circuit open, SQL queue ≥90% saturated, or secure storage noop.
/// - 'healthy': no degradation signals detected.
///
/// Hub consumers should treat absence of 'healthy' as actionable.
String deriveHealthOverallStatus({
  required Map<String, Object?> poolDiagnostics,
  required QueuedDatabaseGateway? queuedGateway,
  required Map<String, Object?>? secureStorage,
}) {
  if (poolDiagnostics['native_circuit_open'] == true) {
    return 'degraded';
  }

  if (queuedGateway != null) {
    final maxSize = queuedGateway.maxQueueSize;
    final currentSize = queuedGateway.queueSize;
    if (maxSize > 0 && currentSize / maxSize >= 0.9) {
      return 'degraded';
    }
  }

  if (secureStorage?['degraded'] == true) {
    return 'degraded';
  }

  return 'healthy';
}
