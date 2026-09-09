import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_heartbeat_controller.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

/// Heartbeat emit/ack wiring extracted from the Socket.IO transport client.
final class SocketIoTransportHeartbeatBridge {
  SocketIoTransportHeartbeatBridge({
    required SocketIoHeartbeatController heartbeat,
    required String Function() agentIdProvider,
    required String Function() protocolNameProvider,
    required Future<bool> Function(String event, dynamic payload) emitEventAsync,
    required void Function(String direction, String event, dynamic data) logMessage,
    required dynamic Function(dynamic data, {required String sourceEvent}) decodeIncomingPayload,
    MetricsCollector? metricsCollector,
  }) : _heartbeat = heartbeat,
       _agentIdProvider = agentIdProvider,
       _protocolNameProvider = protocolNameProvider,
       _emitEventAsync = emitEventAsync,
       _logMessage = logMessage,
       _decodeIncomingPayload = decodeIncomingPayload,
       _metricsCollector = metricsCollector;

  final SocketIoHeartbeatController _heartbeat;
  final String Function() _agentIdProvider;
  final String Function() _protocolNameProvider;
  final Future<bool> Function(String event, dynamic payload) _emitEventAsync;
  final void Function(String direction, String event, dynamic data) _logMessage;
  final dynamic Function(dynamic data, {required String sourceEvent}) _decodeIncomingPayload;
  final MetricsCollector? _metricsCollector;

  SocketIoHeartbeatController get heartbeat => _heartbeat;

  Future<bool> emitAgentHeartbeat([int? heartbeatEpoch]) {
    final agentId = _agentIdProvider();
    final traceId = '${DateTime.now().microsecondsSinceEpoch}-${agentId.hashCode.toUnsigned(20).toRadixString(16)}';
    final payload = <String, dynamic>{
      'agent_id': agentId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'protocol': _protocolNameProvider(),
      'trace_id': traceId,
    };
    if (heartbeatEpoch != null && !_heartbeat.registerExpectedTraceId(traceId, heartbeatEpoch)) {
      return Future<bool>.value(false);
    }
    return _emitEventAsync('agent:heartbeat', payload);
  }

  void logHeartbeatEvent(String direction, String event, dynamic data) {
    final agentId = _agentIdProvider();
    final enriched = data is Map<String, dynamic>
        ? <String, dynamic>{...data, 'agent_id': agentId}
        : <String, dynamic>{'agent_id': agentId, 'payload': data};
    _logMessage(direction, event, enriched);
  }

  void handleHeartbeatAck(dynamic data) {
    dynamic payload = data;
    try {
      payload = _decodeIncomingPayload(
        data,
        sourceEvent: 'hub:heartbeat_ack',
      );
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Invalid hub:heartbeat_ack payload',
        error,
        stackTrace,
      );
      return;
    }
    final traceId = payload is Map<String, dynamic> ? payload['trace_id'] : null;
    final normalizedTraceId = traceId?.toString();
    final rejectionReason = _heartbeat.ackRejectionReason(normalizedTraceId);
    final accepted = _heartbeat.onAckReceived(normalizedTraceId);
    if (rejectionReason != null) {
      _metricsCollector?.recordHeartbeatAckRejected(rejectionReason);
    }
    final logged = traceId != null
        ? <String, dynamic>{
            ...(payload as Map<String, dynamic>),
            'correlated_trace_id': traceId,
            'accepted': accepted,
          }
        : payload;
    _logMessage('RECEIVED', 'hub:heartbeat_ack', logged);
  }
}
