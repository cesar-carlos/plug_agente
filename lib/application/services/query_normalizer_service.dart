import 'dart:isolate';

import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';

class QueryNormalizerService {
  QueryNormalizerService(this._normalizer);
  final QueryNormalizer _normalizer;

  static final RegExp _columnWhitespace = RegExp(r'\s+');
  static final RegExp _columnNonAlnum = RegExp('[^a-z0-9_]');

  /// Row count above which normalization runs in a background isolate so the
  /// UI isolate stays responsive during hub/playground materialized responses.
  static int normalizeIsolateRowThreshold = TransportLimits.defaultStreamingRowThreshold;

  static int totalRowCount(QueryResponse response) {
    if (response.resultSets.isEmpty) {
      return response.data.length;
    }
    var count = 0;
    for (final resultSet in response.resultSets) {
      count += resultSet.rows.length;
    }
    return count;
  }

  /// Normalizes on the current isolate or offloads when [totalRowCount] is high.
  Future<QueryResponse> normalizeAsync(QueryResponse response) async {
    if (totalRowCount(response) < normalizeIsolateRowThreshold) {
      return normalize(response);
    }
    return Isolate.run(() => normalizeQueryResponseInIsolate(response));
  }

  /// Normalizes row maps and column names for RPC/hub consumption (sync CPU work).
  QueryResponse normalize(QueryResponse response) {
    final keyCache = <String, String>{};
    final normalizedData = normalizeRows(
      response.data,
      keyCache: keyCache,
    );
    final normalizedResultSets = response.resultSets
        .map(
          (resultSet) => resultSet.copyWith(
            rows: normalizeRows(
              resultSet.rows,
              keyCache: keyCache,
            ),
          ),
        )
        .toList(growable: false);
    final resultSetByIndex = {
      for (final resultSet in normalizedResultSets) resultSet.index: resultSet,
    };
    final normalizedItems = response.items
        .map((item) {
          if (item.resultSet == null) {
            return item;
          }
          return QueryResponseItem.resultSet(
            index: item.index,
            resultSet: resultSetByIndex[item.resultSet!.index],
          );
        })
        .toList(growable: false);

    return QueryResponse(
      id: response.id,
      requestId: response.requestId,
      agentId: response.agentId,
      data: normalizedData,
      affectedRows: response.affectedRows,
      startedAt: response.startedAt,
      wasTruncated: response.wasTruncated,
      timestamp: response.timestamp,
      error: response.error,
      columnMetadata: response.columnMetadata,
      pagination: response.pagination,
      resultSets: normalizedResultSets,
      items: normalizedItems,
    );
  }

  /// Normalizes a row-set without requiring a full [QueryResponse] wrapper.
  List<Map<String, dynamic>> normalizeRows(
    List<Map<String, dynamic>> rows, {
    Map<String, String>? keyCache,
  }) {
    final normalizedKeyCache = keyCache ?? <String, String>{};
    final normalizedData = <Map<String, dynamic>>[];

    for (final row in rows) {
      final normalizedRow = <String, dynamic>{};

      for (final entry in row.entries) {
        final key = normalizedKeyCache.putIfAbsent(entry.key, () {
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

/// Top-level entry for `Isolate.run` when normalizing large result sets off the UI isolate.
QueryResponse normalizeQueryResponseInIsolate(QueryResponse response) {
  return QueryNormalizerService(QueryNormalizer()).normalize(response);
}
