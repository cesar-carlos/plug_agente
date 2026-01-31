import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/domain/entities/query_response.dart';

class QueryNormalizerService {
  QueryNormalizerService(this._normalizer);
  final QueryNormalizer _normalizer;

  Future<QueryResponse> normalize(QueryResponse response) async {
    final normalizedData = <Map<String, dynamic>>[];

    for (final row in response.data) {
      final normalizedRow = <String, dynamic>{};

      for (final entry in row.entries) {
        final sanitizedKey = _normalizer.sanitizeQuery(entry.key);
        final key = _normalizeColumnName(sanitizedKey);
        normalizedRow[key] = _normalizeValue(entry.value);
      }

      normalizedData.add(normalizedRow);
    }

    return QueryResponse(
      id: response.id,
      requestId: response.requestId,
      agentId: response.agentId,
      data: normalizedData,
      affectedRows: response.affectedRows,
      timestamp: response.timestamp,
      error: response.error,
    );
  }

  String _normalizeColumnName(String columnName) {
    if (columnName.isEmpty) return 'column';

    return columnName
        .replaceAllMapped(RegExp(r'\s+'), (match) => '_')
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9_]'), '');
  }

  dynamic _normalizeValue(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      return value.trim();
    }

    if (value is DateTime) {
      return value.toIso8601String();
    }

    return value;
  }
}
