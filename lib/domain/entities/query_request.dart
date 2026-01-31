// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
// Reason: QueryRequest uses ID-based equality for request tracking.

class QueryRequest {
  const QueryRequest({
    required this.id,
    required this.agentId,
    required this.query,
    required this.timestamp,
    this.parameters,
  });
  final String id;
  final String agentId;
  final String query;
  final Map<String, dynamic>? parameters;
  final DateTime timestamp;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QueryRequest && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
