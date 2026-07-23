import 'dart:isolate';

import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/core/utils/odbc_wire_cell_normalizer.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';

class QueryNormalizerService {
  QueryNormalizerService(this._normalizer);
  final QueryNormalizer _normalizer;

  static final RegExp _columnWhitespace = RegExp(r'\s+');
  static final RegExp _columnNonAlnum = RegExp('[^a-z0-9_]');
  static final RegExp _wireSafeColumnKey = RegExp(r'^[a-z][a-z0-9_]*$');

  /// Row count above which normalization runs in a background isolate so the
  /// UI isolate stays responsive during hub/playground materialized responses.
  static int normalizeIsolateRowThreshold = TransportLimits.defaultStreamingRowThreshold;

  /// Minimum rows before skipping a full key rewrite when keys are already wire-safe.
  static int skipRowRewriteRowThreshold = 64;

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
  Future<QueryResponse> normalizeAsync(
    QueryResponse response, {
    SqlHandlingMode sqlHandlingMode = SqlHandlingMode.managed,
  }) async {
    if (sqlHandlingMode == SqlHandlingMode.preserve) {
      if (totalRowCount(response) < normalizeIsolateRowThreshold) {
        return materializeResponseCells(response);
      }
      return Isolate.run(() => materializeQueryResponseCellsInIsolate(response));
    }
    if (_shouldSkipNormalization(response, sqlHandlingMode: sqlHandlingMode)) {
      return response;
    }
    if (totalRowCount(response) < normalizeIsolateRowThreshold) {
      return normalize(response, sqlHandlingMode: sqlHandlingMode);
    }
    return Isolate.run(() => normalizeQueryResponseInIsolate(response, sqlHandlingMode: sqlHandlingMode));
  }

  /// Normalizes row maps and column names for RPC/hub consumption (sync CPU work).
  QueryResponse normalize(
    QueryResponse response, {
    SqlHandlingMode sqlHandlingMode = SqlHandlingMode.managed,
  }) {
    if (_shouldSkipNormalization(response, sqlHandlingMode: sqlHandlingMode)) {
      return response;
    }
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

  bool _shouldSkipNormalization(
    QueryResponse response, {
    required SqlHandlingMode sqlHandlingMode,
  }) {
    final rowCount = totalRowCount(response);
    if (rowCount < skipRowRewriteRowThreshold) {
      return false;
    }
    return _rowsLookWireSafe(response);
  }

  bool _rowsLookWireSafe(QueryResponse response) {
    if (response.resultSets.isNotEmpty) {
      for (final resultSet in response.resultSets) {
        if (!_rowMapsLookWireSafe(resultSet.rows)) {
          return false;
        }
      }
      return true;
    }
    return _rowMapsLookWireSafe(response.data);
  }

  bool _rowMapsLookWireSafe(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return false;
    }
    for (final row in rows) {
      for (final entry in row.entries) {
        if (!_wireSafeColumnKey.hasMatch(entry.key)) {
          return false;
        }
        if (!_valueLooksWireSafe(entry.value)) {
          return false;
        }
      }
    }
    return true;
  }

  bool _valueLooksWireSafe(dynamic value) {
    if (value == null) {
      return true;
    }
    if (value is String) {
      return value == value.trim();
    }
    if (value is num || value is bool) {
      return true;
    }
    return false;
  }

  String _normalizeColumnName(String columnName) {
    if (columnName.isEmpty) return 'column';

    return columnName.replaceAllMapped(_columnWhitespace, (match) => '_').toLowerCase().replaceAll(_columnNonAlnum, '');
  }

  dynamic _normalizeValue(dynamic value) {
    final materialized = normalizeOdbcWireCell(value);
    if (materialized is String) {
      return materialized.trim();
    }
    return materialized;
  }

  QueryResponse materializeResponseCells(QueryResponse response) {
    final materializedData = _materializeRows(response.data);
    final materializedResultSets = response.resultSets
        .map(
          (resultSet) => resultSet.copyWith(
            rows: _materializeRows(resultSet.rows),
          ),
        )
        .toList(growable: false);
    final resultSetByIndex = {
      for (final resultSet in materializedResultSets) resultSet.index: resultSet,
    };
    final materializedItems = response.items
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
      data: materializedData,
      affectedRows: response.affectedRows,
      startedAt: response.startedAt,
      wasTruncated: response.wasTruncated,
      timestamp: response.timestamp,
      error: response.error,
      columnMetadata: response.columnMetadata,
      pagination: response.pagination,
      resultSets: materializedResultSets,
      items: materializedItems,
    );
  }

  List<Map<String, dynamic>> _materializeRows(List<Map<String, dynamic>> rows) {
    return rows
        .map(
          (row) => <String, dynamic>{
            for (final entry in row.entries) entry.key: normalizeOdbcWireCell(entry.value),
          },
        )
        .toList(growable: false);
  }
}

/// Top-level entry for `Isolate.run` when materializing ODBC cells off the UI isolate.
QueryResponse materializeQueryResponseCellsInIsolate(QueryResponse response) {
  return QueryNormalizerService(QueryNormalizer()).materializeResponseCells(response);
}

/// Top-level entry for `Isolate.run` when normalizing large result sets off the UI isolate.
QueryResponse normalizeQueryResponseInIsolate(
  QueryResponse response, {
  SqlHandlingMode sqlHandlingMode = SqlHandlingMode.managed,
}) {
  return QueryNormalizerService(QueryNormalizer()).normalize(
    response,
    sqlHandlingMode: sqlHandlingMode,
  );
}
