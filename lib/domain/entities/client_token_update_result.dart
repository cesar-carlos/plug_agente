/// Outcome of a client token update operation. Drives audit trail, cache
/// invalidation and UI feedback.
enum ClientTokenUpdateOutcome {
  /// No fields differed from the persisted state. No write was performed.
  unchanged,

  /// Only metadata fields (clientId, name, agentId, payload) changed. The
  /// token secret and authorization policy are preserved.
  metadataOnly,

  /// Authorization policy changed. The token secret is rotated.
  rotated,
}

class ClientTokenUpdateResult {
  const ClientTokenUpdateResult({
    required this.outcome,
    required this.version,
    required this.updatedAt,
    this.tokenValue,
  });

  /// What kind of update happened. UI and audit trail key off this value.
  final ClientTokenUpdateOutcome outcome;

  /// New opaque token value when the underlying secret was rotated.
  /// `null` when the update preserved the existing token (metadata-only edit
  /// or no-op).
  final String? tokenValue;
  final int version;
  final DateTime updatedAt;

  bool get didRotateToken => outcome == ClientTokenUpdateOutcome.rotated;
  bool get didChangeMetadata =>
      outcome == ClientTokenUpdateOutcome.metadataOnly || outcome == ClientTokenUpdateOutcome.rotated;
}
