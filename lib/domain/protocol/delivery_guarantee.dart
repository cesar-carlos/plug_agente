/// Delivery guarantee levels for Socket.IO events.
///
/// Used when `enableSocketDeliveryGuarantees` feature flag is active
/// to classify event types and their expected ack/retry behavior.
enum DeliveryGuarantee {
  /// No acknowledgment; fire-and-forget.
  bestEffort,

  /// At least once: ack expected, retry on failure.
  atLeastOnce,
}

/// Event types for delivery guarantee matrix.
enum DeliveryEventType {
  /// Telemetry, notifications (no response expected).
  telemetry,

  /// Critical request hub -> agent (rpc:request).
  requestCritical,

  /// Critical response agent -> hub (rpc:response).
  responseCritical,
}

/// Delivery guarantee configuration per event type.
///
/// When `enableSocketDeliveryGuarantees` is true:
/// - requestCritical: agent emits rpc:request_ack on receipt; hub may retry
///   if no ack; idempotency prevents duplicate execution.
/// - responseCritical: agent uses emitWithAck when sending rpc:response;
///   retries on ack timeout (controlled max retries).
/// - telemetry: best effort, no ack.
class DeliveryGuaranteeConfig {
  const DeliveryGuaranteeConfig._();

  static const int maxResponseRetries = 3;
  static const Duration responseAckTimeout = Duration(seconds: 10);

  /// Exponential backoff before retrying a timed-out `rpc:response` ack.
  static Duration responseAckRetryDelayAfterAttempt(int zeroBasedAttempt) {
    final clamped = zeroBasedAttempt.clamp(0, 6);
    final ms = 250 * (1 << clamped);
    return Duration(milliseconds: ms.clamp(250, 4000));
  }
}
