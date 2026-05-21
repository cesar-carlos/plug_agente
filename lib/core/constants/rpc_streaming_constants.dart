/// Stable diagnostic `reason` strings for SQL streaming backpressure and transport heartbeat.
abstract final class RpcStreamingConstants {
  static const String backpressureOverflowReason = 'backpressure_overflow';

  static const String missedHeartbeatAckReason = 'missed_heartbeat_ack';
}
