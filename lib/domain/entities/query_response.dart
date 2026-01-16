class QueryResponse {
  final String id;
  final String requestId;
  final String agentId;
  final List<Map<String, dynamic>> data;
  final int? affectedRows;
  final DateTime timestamp;
  final String? error;

  const QueryResponse({
    required this.id,
    required this.requestId,
    required this.agentId,
    required this.data,
    this.affectedRows,
    required this.timestamp,
    this.error,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QueryResponse && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}