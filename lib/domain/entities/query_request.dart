class QueryRequest {
  final String id;
  final String agentId;
  final String query;
  final Map<String, dynamic>? parameters;
  final DateTime timestamp;

  const QueryRequest({
    required this.id,
    required this.agentId,
    required this.query,
    this.parameters,
    required this.timestamp,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QueryRequest && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}