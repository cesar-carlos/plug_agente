/// Stable `error.data.reason` values and related technical message prefixes for
/// strict JSON-RPC batch validation.
abstract final class RpcBatchConstants {
  static const String duplicateRequestIdsReason = 'batch_duplicate_ids';

  static const String exceedsLimitReason = 'batch_exceeds_limit';

  static const String duplicateRequestIdsTechnicalMessagePrefix = 'Batch contains duplicate request IDs: ';

  static const String exceedsLimitTechnicalMessagePrefix = 'Batch exceeds limit: ';
}
