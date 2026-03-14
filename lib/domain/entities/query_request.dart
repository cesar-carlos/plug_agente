// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
// Reason: QueryRequest uses ID-based equality for request tracking.

import 'package:plug_agente/domain/entities/query_pagination.dart';

class QueryRequest {
  const QueryRequest({
    required this.id,
    required this.agentId,
    required this.query,
    required this.timestamp,
    this.parameters,
    this.clientToken,
    this.pagination,
    this.expectMultipleResults = false,
  });
  final String id;
  final String agentId;
  final String query;
  final Map<String, dynamic>? parameters;
  final DateTime timestamp;

  /// Optional client token for authorization (when feature is enabled).
  final String? clientToken;
  final QueryPaginationRequest? pagination;
  final bool expectMultipleResults;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QueryRequest && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
