import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/domain/entities/query_response.dart';

class QueryNormalizerService {
  QueryNormalizerService(this._normalizer);
  final QueryNormalizer _normalizer;

  static final RegExp _columnWhitespace = RegExp(r'\s+');
  static final RegExp _columnNonAlnum = RegExp('[^a-z0-9_]');

  /// Normalizes row maps and column names for RPC/hub consumption (sync CPU work).
  QueryResponse normalize(QueryResponse response) {
    final keyCache = <String, String>{};
    final normalizedData = _normalizeRows(response.data, keyCache);
    final normalizedResultSets = response.resultSets
        .map(
          (resultSet) => resultSet.copyWith(
            rows: _normalizeRows(resultSet.rows, keyCache),
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

  List<Map<String, dynamic>> _normalizeRows(
    List<Map<String, dynamic>> rows,
    Map<String, String> keyCache,
  ) {
    final normalizedData = <Map<String, dynamic>>[];

    for (final row in rows) {
      final normalizedRow = <String, dynamic>{};

      for (final entry in row.entries) {
        final key = keyCache.putIfAbsent(entry.key, () {
          final sanitizedKey = _normalizer.sanitizeQuery(entry.key);
          return _normalizeColumnName(sanitizedKey);
        });
        normalizedRow[key] = _normalizeValue(entry.value);
      }

      normalizedData.add(normalizedRow);
    }

    return normalizedData;
  }

  String _normalizeColumnName(String columnName) {
    if (columnName.isEmpty) return 'column';

    return columnName.replaceAllMapped(_columnWhitespace, (match) => '_').toLowerCase().replaceAll(_columnNonAlnum, '');
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
