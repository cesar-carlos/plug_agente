enum TokenAuditEventType {
  create,
  revoke,
  revokedInSession,
  delete,
}

class TokenAuditEvent {
  const TokenAuditEvent({
    required this.eventType,
    required this.timestamp,
    this.clientId,
    this.tokenId,
    this.metadata = const <String, dynamic>{},
  });

  final TokenAuditEventType eventType;
  final DateTime timestamp;
  final String? clientId;
  final String? tokenId;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'event_type': eventType.name,
      'timestamp': timestamp.toIso8601String(),
      if (clientId != null) 'client_id': clientId,
      if (tokenId != null) 'token_id': tokenId,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}
