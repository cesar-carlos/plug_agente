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
      if (totalRowCount(response) >= normalizeIsolateRowThreshold) {
        if (!_needsCellMaterialization(response)) {
          return response;
        }
        return Isolate.run(() => materializeQueryResponseCellsInIsolate(response));
      }
      return materializeResponseCells(response);
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
    return _replaceRows(
      response,
      (rows) => normalizeRows(rows, keyCache: keyCache),
    );
  }

  /// Normalizes a row-set without requiring a full [QueryResponse] wrapper.
  List<Map<String, dynamic>> normalizeRows(
    List<Map<String, dynamic>> rows, {
    Map<String, String>? keyCache,
  }) {
    final normalizedKeyCache = keyCache ?? <String, String>{};
    return _reuseUnchangedRows(
      rows,
      (row) => _normalizeRow(row, normalizedKeyCache),
    );
  }

  Map<String, dynamic> _normalizeRow(
    Map<String, dynamic> row,
    Map<String, String> keyCache,
  ) {
    Map<String, dynamic>? rewritten;
    var seen = 0;
    for (final entry in row.entries) {
      final key = keyCache.putIfAbsent(entry.key, () {
        final sanitizedKey = _normalizer.sanitizeQuery(entry.key);
        return _normalizeColumnName(sanitizedKey);
      });
      final value = _normalizeValue(entry.value);
      if (rewritten == null && key == entry.key && identical(value, entry.value)) {
        seen++;
        continue;
      }
      rewritten ??= _unchangedPrefix(row, seen);
      rewritten[key] = value;
      seen++;
    }
    return rewritten ?? row;
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
    final safeKeys = <String>{};
    for (final row in rows) {
      for (final entry in row.entries) {
        if (safeKeys.add(entry.key) && !_wireSafeColumnKey.hasMatch(entry.key)) {
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
    return _replaceRows(response, _materializeRows);
  }

  bool _needsCellMaterialization(QueryResponse response) {
    if (_rowsNeedCellMaterialization(response.data)) {
      return true;
    }
    for (final resultSet in response.resultSets) {
      if (identical(resultSet.rows, response.data)) {
        continue;
      }
      if (_rowsNeedCellMaterialization(resultSet.rows)) {
        return true;
      }
    }
    return false;
  }

  bool _rowsNeedCellMaterialization(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      for (final value in row.values) {
        if (odbcWireCellNeedsMaterialization(value)) {
          return true;
        }
      }
    }
    return false;
  }

  List<Map<String, dynamic>> _materializeRows(List<Map<String, dynamic>> rows) {
    return _reuseUnchangedRows(rows, _materializeRow);
  }

  Map<String, dynamic> _materializeRow(Map<String, dynamic> row) {
    Map<String, dynamic>? rewritten;
    var seen = 0;
    for (final entry in row.entries) {
      final value = normalizeOdbcWireCell(entry.value);
      if (rewritten == null && identical(value, entry.value)) {
        seen++;
        continue;
      }
      rewritten ??= _unchangedPrefix(row, seen);
      rewritten[entry.key] = value;
      seen++;
    }
    return rewritten ?? row;
  }

  QueryResponse _replaceRows(
    QueryResponse response,
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>> rows) rewriteRows,
  ) {
    final data = rewriteRows(response.data);
    final resultSets = <QueryResultSet>[];
    var resultSetsChanged = false;
    for (final resultSet in response.resultSets) {
      final rows = rewriteRows(resultSet.rows);
      if (identical(rows, resultSet.rows)) {
        resultSets.add(resultSet);
        continue;
      }
      resultSetsChanged = true;
      resultSets.add(resultSet.copyWith(rows: rows));
    }
    if (identical(data, response.data) && !resultSetsChanged) {
      return response;
    }

    final resultSetByIndex = {for (final resultSet in resultSets) resultSet.index: resultSet};
    final items = response.items
        .map((item) {
          final resultSet = item.resultSet;
          if (resultSet == null) {
            return item;
          }
          final replacement = resultSetByIndex[resultSet.index];
          if (identical(replacement, resultSet)) {
            return item;
          }
          return QueryResponseItem.resultSet(
            index: item.index,
            resultSet: replacement,
          );
        })
        .toList(growable: false);

    return QueryResponse(
      id: response.id,
      requestId: response.requestId,
      agentId: response.agentId,
      data: data,
      affectedRows: response.affectedRows,
      startedAt: response.startedAt,
      wasTruncated: response.wasTruncated,
      timestamp: response.timestamp,
      error: response.error,
      columnMetadata: response.columnMetadata,
      pagination: response.pagination,
      resultSets: resultSetsChanged ? resultSets : response.resultSets,
      items: items,
    );
  }

  List<Map<String, dynamic>> _reuseUnchangedRows(
    List<Map<String, dynamic>> rows,
    Map<String, dynamic> Function(Map<String, dynamic> row) rewriteRow,
  ) {
    List<Map<String, dynamic>>? rewritten;
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final next = rewriteRow(row);
      if (rewritten == null) {
        if (identical(next, row)) {
          continue;
        }
        rewritten = List<Map<String, dynamic>>.of(rows);
      }
      rewritten[index] = next;
    }
    return rewritten ?? rows;
  }

  Map<String, dynamic> _unchangedPrefix(Map<String, dynamic> row, int count) {
    final prefix = <String, dynamic>{};
    var index = 0;
    for (final entry in row.entries) {
      if (index == count) {
        break;
      }
      prefix[entry.key] = entry.value;
      index++;
    }
    return prefix;
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
