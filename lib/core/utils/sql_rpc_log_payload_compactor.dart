/// Builds lightweight log/dashboard snapshots for SQL JSON-RPC responses.
///
/// This intentionally changes only diagnostic payloads. The public
/// `rpc:response` wire payload must keep its original rows and metadata.
class SqlRpcLogPayloadCompactor {
  const SqlRpcLogPayloadCompactor._();

  static const String socketRowsMarker = 'omitted_from_socket_log';
  static const String dashboardRowsMarker = 'omitted';

  static dynamic compactSocketLogPayload(String event, dynamic data) {
    if (event != 'rpc:response' || data is! Map) {
      return data;
    }
    final result = data['result'];
    if (result is! Map || !hasSqlResultPayloadForPreview(result)) {
      return data;
    }
    return <String, dynamic>{
      if (data['jsonrpc'] != null) 'jsonrpc': data['jsonrpc'],
      if (data['id'] != null) 'id': data['id'],
      'result': compactResultSnapshot(result, rowsMarker: socketRowsMarker),
    };
  }

  static Map<String, dynamic> dashboardDataSnapshot(String event, dynamic data) {
    if (data is! Map) {
      return <String, dynamic>{'payload': 'omitted'};
    }
    switch (event) {
      case 'rpc:chunk':
        final rows = data['rows'];
        return <String, dynamic>{
          if (data['stream_id'] != null) 'stream_id': data['stream_id'],
          if (data['request_id'] != null) 'request_id': data['request_id'],
          'chunk_index': data['chunk_index'],
          'row_count': rows is List ? rows.length : 0,
          'rows': dashboardRowsMarker,
        };
      case 'rpc:complete':
        return <String, dynamic>{
          if (data['stream_id'] != null) 'stream_id': data['stream_id'],
          if (data['request_id'] != null) 'request_id': data['request_id'],
          if (data['total_rows'] != null) 'total_rows': data['total_rows'],
          if (data['terminal_status'] != null) 'terminal_status': data['terminal_status'],
        };
      case 'rpc:response':
        final result = data['result'];
        if (result is Map && hasSqlResultPayloadForPreview(result)) {
          return <String, dynamic>{
            if (data['id'] != null) 'id': data['id'],
            'result': compactResultSnapshot(
              result,
              rowsMarker: dashboardRowsMarker,
              includeExistingColumnMetadataCount: true,
            ),
          };
        }
        return <String, dynamic>{'payload': 'omitted'};
      case 'rpc:request':
        final params = data['params'];
        final sql = params is Map ? params['sql'] : null;
        final sqlPreview = sql is String && sql.length > 160 ? '${sql.substring(0, 160)}...' : sql;
        return <String, dynamic>{
          if (data['id'] != null) 'id': data['id'],
          'method': data['method'],
          'sql_preview': ?sqlPreview,
        };
      default:
        return <String, dynamic>{'payload': 'omitted'};
    }
  }

  static String? rpcResponsePreview(Map<dynamic, dynamic> data) {
    final result = data['result'];
    if (result is! Map || !hasSqlResultPayloadForPreview(result)) {
      return null;
    }

    final resultSets = result['result_sets'];
    final items = result['items'];
    final resultSetCount = resultSets is List ? resultSets.length : result['result_set_count'];
    final resultSetText = resultSetCount != null ? ' result_sets=$resultSetCount' : '';
    final columnCount = _columnMetadataCount(result);
    final columnText = columnCount != null ? ' columns=$columnCount' : '';
    final itemCount = items is List ? items.length : result['item_count'];
    final itemText = itemCount != null ? ' items=$itemCount' : '';
    final rowCount = items is List ? batchItemsRowCount(items) : resultRowCount(result);
    return 'id=${data['id']} row_count=$rowCount'
        '$itemText '
        'affected_rows=${intValue(result['affected_rows'])}'
        '$resultSetText$columnText '
        '(${result['started_at']} -> ${result['finished_at']}) '
        '(row payload omitted from dashboard feed)';
  }

  static Map<String, dynamic> compactResultSnapshot(
    Map<dynamic, dynamic> result, {
    required String rowsMarker,
    bool includeExistingColumnMetadataCount = false,
  }) {
    final rows = result['rows'];
    final resultSets = result['result_sets'];
    final items = result['items'];
    final columnMetadata = result['column_metadata'];
    final columnMetadataCount = columnMetadata is List
        ? columnMetadata.length
        : includeExistingColumnMetadataCount
        ? result['column_metadata_count']
        : null;

    return <String, dynamic>{
      if (result['execution_id'] != null) 'execution_id': result['execution_id'],
      if (result['stream_id'] != null) 'stream_id': result['stream_id'],
      if (_shouldIncludeResultRowCount(result)) 'row_count': resultRowCount(result),
      if (result['returned_rows'] != null) 'returned_rows': result['returned_rows'],
      if (result['affected_rows'] != null) 'affected_rows': result['affected_rows'],
      if (result['started_at'] != null) 'started_at': result['started_at'],
      if (result['finished_at'] != null) 'finished_at': result['finished_at'],
      if (result['sql_handling_mode'] != null) 'sql_handling_mode': result['sql_handling_mode'],
      if (result['max_rows_handling'] != null) 'max_rows_handling': result['max_rows_handling'],
      if (result['truncated'] != null) 'truncated': result['truncated'],
      if (result['total_commands'] != null) 'total_commands': result['total_commands'],
      if (result['successful_commands'] != null) 'successful_commands': result['successful_commands'],
      if (result['failed_commands'] != null) 'failed_commands': result['failed_commands'],
      if (items is List) 'item_count': items.length,
      if (items is List) 'total_item_rows': batchItemsRowCount(items),
      if (items is List) 'items': compactBatchItems(items, rowsMarker: rowsMarker),
      if (rows is List || isOmittedRowsMarker(rows)) 'rows': rowsMarker,
      if (resultSets is List) 'result_set_count': resultSets.length,
      if (resultSets is! List && result['result_set_count'] != null) 'result_set_count': result['result_set_count'],
      if (resultSets is List) 'total_result_set_rows': resultSetRowCount(resultSets),
      if (resultSets is List) 'result_sets': compactResultSets(resultSets, rowsMarker: rowsMarker),
      if (resultSets is! List && isOmittedRowsMarker(resultSets)) 'result_sets': rowsMarker,
      'column_metadata_count': ?columnMetadataCount,
    };
  }

  static List<Map<String, dynamic>> compactBatchItems(
    List<dynamic> items, {
    required String rowsMarker,
  }) {
    return items
        .whereType<Map<dynamic, dynamic>>()
        .map((item) {
          final rows = item['rows'];
          final columnMetadata = item['column_metadata'];
          return <String, dynamic>{
            if (item['index'] != null) 'index': item['index'],
            if (item['ok'] != null) 'ok': item['ok'],
            if (item['row_count'] != null) 'row_count': item['row_count'],
            if (item['affected_rows'] != null) 'affected_rows': item['affected_rows'],
            if (item['error'] != null) 'error': item['error'],
            if (rows is List || isOmittedRowsMarker(rows)) 'rows': rowsMarker,
            if (columnMetadata is List) 'column_metadata_count': columnMetadata.length,
            if (columnMetadata is! List && item['column_metadata_count'] != null)
              'column_metadata_count': item['column_metadata_count'],
          };
        })
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> compactResultSets(
    List<dynamic> resultSets, {
    required String rowsMarker,
  }) {
    return resultSets
        .whereType<Map<dynamic, dynamic>>()
        .map((set) {
          final rows = set['rows'];
          final columnMetadata = set['column_metadata'];
          return <String, dynamic>{
            if (set['name'] != null) 'name': set['name'],
            if (set['index'] != null) 'index': set['index'],
            if (set['row_count'] != null) 'row_count': set['row_count'],
            if (set['returned_rows'] != null) 'returned_rows': set['returned_rows'],
            if (rows is List || isOmittedRowsMarker(rows)) 'rows': rowsMarker,
            if (columnMetadata is List) 'column_metadata_count': columnMetadata.length,
            if (columnMetadata is! List && set['column_metadata_count'] != null)
              'column_metadata_count': set['column_metadata_count'],
          };
        })
        .toList(growable: false);
  }

  static int intValue(dynamic value) {
    return value is num ? value.toInt() : 0;
  }

  static int resultSetRowCount(dynamic resultSets) {
    if (resultSets is! List) {
      return 0;
    }
    var total = 0;
    for (final item in resultSets) {
      if (item is! Map) {
        continue;
      }
      final rowCount = item['row_count'];
      if (rowCount is num) {
        total += rowCount.toInt();
        continue;
      }
      final returnedRows = item['returned_rows'];
      if (returnedRows is num) {
        total += returnedRows.toInt();
        continue;
      }
      final rows = item['rows'];
      if (rows is List) {
        total += rows.length;
      }
    }
    return total;
  }

  static int resultRowCount(Map<dynamic, dynamic> result) {
    final rowCount = result['row_count'];
    if (rowCount is num) {
      return rowCount.toInt();
    }
    final returnedRows = result['returned_rows'];
    if (returnedRows is num) {
      return returnedRows.toInt();
    }
    final rows = result['rows'];
    if (rows is List) {
      return rows.length;
    }
    return resultSetRowCount(result['result_sets']);
  }

  static int batchItemsRowCount(dynamic items) {
    if (items is! List) {
      return 0;
    }
    var total = 0;
    for (final item in items) {
      if (item is! Map) {
        continue;
      }
      final rowCount = item['row_count'];
      if (rowCount is num) {
        total += rowCount.toInt();
        continue;
      }
      final rows = item['rows'];
      if (rows is List) {
        total += rows.length;
      }
    }
    return total;
  }

  static bool isOmittedRowsMarker(dynamic value) {
    return value is String && value.startsWith('omitted');
  }

  static bool hasSqlResultPayloadForPreview(Map<dynamic, dynamic> result) {
    final rows = result['rows'];
    final resultSets = result['result_sets'];
    final items = result['items'];
    return result['stream_id'] != null ||
        items is List ||
        rows is List ||
        resultSets is List ||
        isOmittedRowsMarker(rows) ||
        isOmittedRowsMarker(resultSets);
  }

  static bool _shouldIncludeResultRowCount(Map<dynamic, dynamic> result) {
    return result['row_count'] != null ||
        result['returned_rows'] != null ||
        result['rows'] is List ||
        result['result_sets'] is List;
  }

  static dynamic _columnMetadataCount(Map<dynamic, dynamic> result) {
    final columnMetadata = result['column_metadata'];
    if (columnMetadata is List) {
      return columnMetadata.length;
    }
    return result['column_metadata_count'];
  }
}
