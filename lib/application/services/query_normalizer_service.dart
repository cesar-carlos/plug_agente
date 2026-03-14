import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/domain/entities/query_response.dart';

class QueryNormalizerService {
  QueryNormalizerService(this._normalizer);
  final QueryNormalizer _normalizer;

  Future<QueryResponse> normalize(QueryResponse response) async {
    final normalizedData = _normalizeRows(response.data);
    final normalizedResultSets = response.resultSets
        .map(
          (resultSet) => resultSet.copyWith(
            rows: _normalizeRows(resultSet.rows),
          ),
        )
        .toList(growable: false);
    final normalizedItems = response.items
        .map((item) {
          if (item.resultSet == null) {
            return item;
          }
          return QueryResponseItem.resultSet(
            index: item.index,
            resultSet: normalizedResultSets[item.resultSet!.index],
          );
        })
        .toList(growable: false);

    return QueryResponse(
      id: response.id,
      requestId: response.requestId,
      agentId: response.agentId,
      data: normalizedData,
      affectedRows: response.affectedRows,
      timestamp: response.timestamp,
      error: response.error,
      columnMetadata: response.columnMetadata,
      pagination: response.pagination,
      resultSets: normalizedResultSets,
      items: normalizedItems,
    );
  }

  List<Map<String, dynamic>> _normalizeRows(List<Map<String, dynamic>> rows) {
    final normalizedData = <Map<String, dynamic>>[];

    for (final row in rows) {
      final normalizedRow = <String, dynamic>{};

      for (final entry in row.entries) {
        final sanitizedKey = _normalizer.sanitizeQuery(entry.key);
        final key = _normalizeColumnName(sanitizedKey);
        normalizedRow[key] = _normalizeValue(entry.value);
      }

      normalizedData.add(normalizedRow);
    }

    return normalizedData;
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
