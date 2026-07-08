import 'package:plug_agente/core/constants/connection_constants_env.dart';

/// Drift persistence purge intervals and retention for RPC idempotency and agent actions.
abstract final class ConnectionPersistenceConstants {
  ConnectionPersistenceConstants._();

  /// Wall-clock interval for best-effort purge of expired rows in the persisted
  /// RPC idempotency cache (Drift). Independent of per-entry TTL applied when
  /// caching successful idempotent RPC responses.
  static const Duration rpcIdempotencyExpiredPurgeInterval = Duration(minutes: 15);

  /// TTL for each persisted RPC idempotency cache entry (SQLite `expires_at`).
  ///
  /// Override with env `RPC_IDEMPOTENCY_CACHE_TTL_SECONDS` (integer seconds).
  /// Clamped to 60..86400 (1 minute through 24 hours). Default 300 (5 minutes).
  static Duration get rpcIdempotencyEntryTtl {
    final parsed = int.tryParse(ConnectionConstantsEnv.optional('RPC_IDEMPOTENCY_CACHE_TTL_SECONDS') ?? '');
    final seconds = (parsed == null || parsed <= 0) ? 300 : parsed.clamp(60, 86400);
    return Duration(seconds: seconds);
  }

  /// TTL for cached successful responses of `agent.action.run` and
  /// `agent.action.validateRun` in the persisted idempotency store (Drift).
  ///
  /// Default: min([agentActionExecutionRetention], 24 h) so Hub retries after
  /// reconnect still hit the RPC cache while limiting SQLite growth. Dedup beyond
  /// this window uses persisted `agent_action_execution` rows (same
  /// `action_id` + `idempotency_key`) until execution history retention.
  ///
  /// Override with env `AGENT_ACTION_RPC_IDEMPOTENCY_CACHE_TTL_SECONDS` (60..259200).
  static Duration get agentActionRpcIdempotencyEntryTtl {
    final parsed = int.tryParse(
      ConnectionConstantsEnv.optional('AGENT_ACTION_RPC_IDEMPOTENCY_CACHE_TTL_SECONDS') ?? '',
    );
    if (parsed != null && parsed > 0) {
      return Duration(seconds: parsed.clamp(60, 259200));
    }
    final retentionSeconds = agentActionExecutionRetention.inSeconds;
    final defaultSeconds = retentionSeconds > 86400 ? 86400 : retentionSeconds;
    return Duration(seconds: defaultSeconds < 60 ? 60 : defaultSeconds);
  }

  /// Wall-clock interval for best-effort purge of old rows in the append-only
  /// `agent_action_remote_audit` table (Drift).
  static const Duration agentActionRemoteAuditPurgeInterval = Duration(minutes: 15);

  /// Retention window for `agent_action_remote_audit.occurred_at` (UTC).
  ///
  /// Override with env `AGENT_ACTION_REMOTE_AUDIT_RETENTION_DAYS` (integer days).
  /// Clamped to 7..3650. Default 90.
  static Duration get agentActionRemoteAuditRetention {
    final parsed = int.tryParse(ConnectionConstantsEnv.optional('AGENT_ACTION_REMOTE_AUDIT_RETENTION_DAYS') ?? '');
    final days = (parsed == null || parsed <= 0) ? 90 : parsed.clamp(7, 3650);
    return Duration(days: days);
  }

  /// Wall-clock interval for best-effort purge of **terminal** rows in
  /// `agent_action_execution` older than [agentActionExecutionRetention].
  static const Duration agentActionExecutionPurgeInterval = Duration(minutes: 15);

  /// Retention window for persisted terminal `agent_action_execution` history.
  ///
  /// Override with env `AGENT_ACTION_EXECUTION_RETENTION_DAYS` (integer days).
  /// Clamped to 1..3650. Default 3.
  static Duration get agentActionExecutionRetention {
    final parsed = int.tryParse(ConnectionConstantsEnv.optional('AGENT_ACTION_EXECUTION_RETENTION_DAYS') ?? '');
    final days = (parsed == null || parsed <= 0) ? 3 : parsed.clamp(1, 3650);
    return Duration(days: days);
  }

  /// Wall-clock interval for clearing stored stdout/stderr on old terminal executions.
  static const Duration agentActionCapturedOutputPurgeInterval = Duration(minutes: 15);

  /// Retention for redacted stdout/stderr columns on terminal `agent_action_execution` rows.
  ///
  /// Shorter than [agentActionExecutionRetention]: metadata stays until history purge,
  /// captured blobs are cleared earlier to limit SQLite growth.
  ///
  /// Override with env `AGENT_ACTION_CAPTURED_OUTPUT_RETENTION_HOURS` (1..720). Default 24.
  static Duration get agentActionCapturedOutputRetention {
    final parsed = int.tryParse(ConnectionConstantsEnv.optional('AGENT_ACTION_CAPTURED_OUTPUT_RETENTION_HOURS') ?? '');
    final hours = (parsed == null || parsed <= 0) ? 24 : parsed.clamp(1, 720);
    final duration = Duration(hours: hours);
    final historyRetention = agentActionExecutionRetention;
    return duration > historyRetention ? historyRetention : duration;
  }
}
