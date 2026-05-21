/// Stable diagnostic strings for inbound RPC handling (`reason`, `errorReason`,
/// `failure_code` in error extras, and fixed validation messages).
abstract final class RpcInboundConstants {
  static const String protocolNotReadyReason = 'protocol_not_ready';

  /// Hub should reduce parallelism (distinct from window-based rate limiting).
  static const String concurrentHandlersExceededReason = 'concurrent_handlers_exceeded';

  /// Sliding-window limit from RpcRequestGuard (same RPC code as generic rate limit).
  static const String rateWindowExceededReason = 'rate_window_exceeded';

  /// `failure_code` in error data when the single-request handler throws unexpectedly.
  static const String unhandledExceptionFailureCode = 'unhandled_exception';

  /// `failure_code` in error data when the batch handler throws unexpectedly.
  static const String unhandledBatchExceptionFailureCode = 'unhandled_batch_exception';

  /// Technical message when the single-request handler throws unexpectedly.
  static const String unhandledSingleRequestTechnicalMessage = 'Unhandled exception in RPC request handler';

  /// Technical message when the batch handler throws unexpectedly.
  static const String unhandledBatchProcessingTechnicalMessage = 'Unhandled exception in batch processing';

  /// Technical message and Problem Details `detail` for an empty JSON-RPC batch envelope.
  static const String batchRequestEmptyDetail = 'Batch request cannot be empty';

  static String concurrentHandlersExceededTechnicalMessage(int maxConcurrentHandlers) =>
      'Concurrent RPC handler limit exceeded ($maxConcurrentHandlers)';

  static const String protocolNotReadyTechnicalMessage =
      'Protocol not ready: agent:capabilities has not been received yet';

  static const String requestMustBeJsonObjectTechnicalMessage = 'Request must be a JSON object';

  static const String requestExceedsPayloadLimitTechnicalMessage = 'Request exceeds negotiated payload limit';

  static const String batchRequestExceedsPayloadLimitTechnicalMessage =
      'Batch request exceeds negotiated payload limit';

  static const String eachBatchElementMustBeJsonObjectTechnicalMessage =
      'Each element in a batch must be a JSON object';

  static const String invalidPayloadSignatureTechnicalMessage = 'Invalid payload signature';

  static const String nullIdNotificationsCompatibilityTechnicalMessage =
      'id: null notifications require negotiated compatibility';

  static const String unexpectedGuardResultTechnicalMessage = 'Unexpected guard result';

  static const String rateLimitExceededForRpcRequestTechnicalMessage = 'Rate limit exceeded for rpc:request';

  static const String duplicateRequestIdWithinReplayWindowTechnicalMessage =
      'Duplicate request id within replay window';
}
