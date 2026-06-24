import 'package:plug_agente/domain/protocol/transport_extension_negotiation.dart';
import 'package:plug_agente/domain/services/i_agent_health_status_provider.dart';

/// Attaches a compact health snapshot to unary RPC responses on a fixed interval.
final class RpcHealthPiggybackSampler {
  RpcHealthPiggybackSampler({
    required IAgentHealthStatusProvider? healthService,
    required HealthPiggybackNegotiation Function() negotiationProvider,
  }) : _healthService = healthService,
       _negotiationProvider = negotiationProvider;

  final IAgentHealthStatusProvider? _healthService;
  final HealthPiggybackNegotiation Function() _negotiationProvider;
  int _unaryResponseCount = 0;

  Map<String, Object?>? maybeSample(Map<String, dynamic> negotiatedExtensions) {
    if (TransportExtensionNegotiation.parseHealthPiggyback(negotiatedExtensions) == null) {
      return null;
    }
    final healthService = _healthService;
    if (healthService == null) {
      return null;
    }
    final negotiation = _negotiationProvider();
    _unaryResponseCount++;
    if (_unaryResponseCount % negotiation.intervalRequests != 0) {
      return null;
    }
    return _buildSnapshot(healthService, negotiation.freshnessThresholdMs);
  }

  void reset() {
    _unaryResponseCount = 0;
  }

  static Map<String, Object?> _buildSnapshot(
    IAgentHealthStatusProvider healthService,
    int freshnessThresholdMs,
  ) {
    final status = healthService.getHealthStatus();
    final pool = status['pool'] as Map<String, Object?>? ?? const <String, Object?>{};
    final streaming = status['streaming'] as Map<String, Object?>? ?? const <String, Object?>{};
    final sqlQueue = status['sql_queue'] as Map<String, Object?>? ?? const <String, Object?>{};

    final maxQueue = (sqlQueue['max_size'] as num?)?.toInt() ?? 0;
    final currentQueue = (sqlQueue['current_size'] as num?)?.toInt() ?? 0;
    final queuePressure = maxQueue > 0 ? (currentQueue / maxQueue).clamp(0.0, 1.0) : 0.0;

    final circuitOpen = pool['native_circuit_open'] == true;
    final circuitState = circuitOpen ? 'open' : 'closed';

    return <String, Object?>{
      'captured_at_ms': DateTime.now().millisecondsSinceEpoch,
      'freshness_threshold_ms': freshnessThresholdMs,
      'sql_queue_pressure': queuePressure,
      'active_streams': (streaming['active_streams'] as num?)?.toInt() ?? 0,
      'circuit_state': circuitState,
      'status': status['status'] ?? 'healthy',
    };
  }
}
