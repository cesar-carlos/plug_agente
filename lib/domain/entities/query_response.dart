// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
// Reason: QueryResponse uses ID-based equality for response tracking.

class QueryResponse {
  const QueryResponse({
    required this.id,
    required this.requestId,
    required this.agentId,
    required this.data,
    required this.timestamp,
    this.affectedRows,
    this.error,
    this.columnMetadata,
  });
  final String id;
  final String requestId;
  final String agentId;
  final List<Map<String, dynamic>> data;
  final int? affectedRows;
  final DateTime timestamp;
  final String? error;
  final List<Map<String, dynamic>>? columnMetadata;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QueryResponse && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
