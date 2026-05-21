/// Stable `failure.context['reason']` values for the in-process agent action execution queue.
abstract final class AgentActionQueueConstants {
  static const String queuedExecutionNotFoundReason = 'queued_execution_not_found';

  static const String concurrencyLimitReachedReason = 'concurrency_limit_reached';

  static const String concurrencyIgnoreReason = 'concurrency_ignore';

  static const String queueFullReason = 'queue_full';

  static const String queueTimeoutReason = 'queue_timeout';

  static const String queueCancelledReason = 'queue_cancelled';
}
