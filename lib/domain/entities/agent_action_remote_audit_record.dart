/// Append-only audit row for remote `agent.action.*` RPC (no secrets, no raw SQL).
final class AgentActionRemoteAuditRecord {
  const AgentActionRemoteAuditRecord({
    required this.id,
    required this.occurredAtUtc,
    required this.rpcMethod,
    required this.outcome,
    required this.credentialPresent,
    this.actionId,
    this.executionId,
    this.traceId,
    this.requestedBy,
    this.reasonCode,
    this.rpcErrorCode,
    this.clientId,
    this.tokenJti,
    this.runtimeInstanceId,
    this.runtimeSessionId,
    this.idempotencyKey,
  });

  final String id;
  final DateTime occurredAtUtc;
  final String rpcMethod;
  final String outcome;
  final bool credentialPresent;
  final String? actionId;
  final String? executionId;
  final String? traceId;
  final String? requestedBy;
  final String? reasonCode;
  final int? rpcErrorCode;

  /// OAuth-style client id from resolved `ClientTokenPolicy` when available.
  final String? clientId;

  /// JWT `jti` / token id from resolved policy when available (no raw token).
  final String? tokenJti;

  /// Stable per-installation runtime id captured at RPC completion time.
  final String? runtimeInstanceId;

  /// Per-boot runtime session id captured at RPC completion time.
  final String? runtimeSessionId;

  /// Business idempotency key from `agent.action.run` / `validateRun` params or execution row.
  final String? idempotencyKey;
}
