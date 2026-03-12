class ClientTokenSummary {
  const ClientTokenSummary({
    required this.id,
    required this.clientId,
    required this.createdAt,
    required this.isRevoked,
  });

  factory ClientTokenSummary.fromJson(Map<String, dynamic> json) {
    return ClientTokenSummary(
      id: json['id'] as String? ?? '',
      clientId: json['client_id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(
            json['created_at'] as String? ?? '',
          ) ??
          DateTime.now(),
      isRevoked: json['is_revoked'] as bool? ?? false,
    );
  }

  final String id;
  final String clientId;
  final DateTime createdAt;
  final bool isRevoked;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'client_id': clientId,
      'created_at': createdAt.toUtc().toIso8601String(),
      'is_revoked': isRevoked,
    };
  }
}
