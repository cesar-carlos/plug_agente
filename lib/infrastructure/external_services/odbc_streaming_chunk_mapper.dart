import 'dart:convert';
import 'dart:typed_data';

import 'package:odbc_fast/odbc_fast.dart';

/// Input for [mapQueryRowsToChunks].
class OdbcStreamingChunkMapperInput {
  const OdbcStreamingChunkMapperInput({
    required this.columns,
    required this.rows,
    required this.fetchSize,
  });

  final List<String> columns;
  final List<List<dynamic>> rows;
  final int fetchSize;
}

/// Normalizes a streaming fetch size to a positive row count.
int effectiveStreamingFetchSize(int fetchSize) {
  return fetchSize > 0 ? fetchSize : 1000;
}

/// Whether an ODBC-delivered batch can be emitted without re-chunking.
bool shouldSkipRechunk(int rowCount, int fetchSize) {
  return rowCount > 0 && rowCount <= effectiveStreamingFetchSize(fetchSize);
}

/// Normalizes one ODBC cell for Hub/playground row-map streaming.
///
/// SQL Anywhere may return text timestamps, lazy strings, and binary payloads
/// that must be materialized before UI or JSON consumers read them.
Object? normalizeOdbcStreamingCell(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is LazyString) {
    return value.value;
  }
  if (value is DateTime) {
    return value.toIso8601String();
  }
  if (value is Uint8List) {
    return base64Encode(value);
  }
  if (value is List<int>) {
    return base64Encode(value);
  }
  return value;
}

/// Maps one ODBC row vector into the row-map shape emitted by streaming RPC.
Map<String, dynamic> mapOdbcRowToStreamingMap(
  List<String> columns,
  List<dynamic> row,
) {
  final mappedRow = <String, dynamic>{};
  for (var i = 0; i < columns.length; i++) {
    mappedRow[columns[i]] = normalizeOdbcStreamingCell(row[i]);
  }
  return mappedRow;
}

/// Emits row-major ODBC chunks through the shared streaming row-map mapper.
Future<void> emitMappedRowMajorChunks({
  required List<String> columns,
  required List<List<dynamic>> rows,
  required int fetchSize,
  required Future<void> Function(List<Map<String, dynamic>> chunk) onChunk,
  bool Function()? isCancelRequested,
}) async {
  final chunks = mapQueryRowsToChunks(
    OdbcStreamingChunkMapperInput(
      columns: columns,
      rows: rows,
      fetchSize: fetchSize,
    ),
  );

  for (final chunk in chunks) {
    await onChunk(chunk);
    if (chunks.length > 1) {
      await Future<void>.delayed(Duration.zero);
    }
    if (isCancelRequested?.call() ?? false) {
      return;
    }
  }
}

/// Maps ODBC row vectors into fetch-sized chunks for the Hub wire format.
List<List<Map<String, dynamic>>> mapQueryRowsToChunks(
  OdbcStreamingChunkMapperInput input,
) {
  if (input.rows.isEmpty) {
    return const <List<Map<String, dynamic>>>[];
  }

  final safeFetchSize = effectiveStreamingFetchSize(input.fetchSize);
  if (shouldSkipRechunk(input.rows.length, safeFetchSize)) {
    return <List<Map<String, dynamic>>>[
      mapQueryResultRows(input.columns, input.rows),
    ];
  }

  final chunks = <List<Map<String, dynamic>>>[];
  var chunk = <Map<String, dynamic>>[];

  for (final row in input.rows) {
    chunk.add(mapOdbcRowToStreamingMap(input.columns, row));
    if (chunk.length >= safeFetchSize) {
      chunks.add(List<Map<String, dynamic>>.from(chunk));
      chunk = <Map<String, dynamic>>[];
    }
  }

  if (chunk.isNotEmpty) {
    chunks.add(chunk);
  }

  return chunks;
}

/// Maps all ODBC rows in one batch to the Hub row-map wire shape.
List<Map<String, dynamic>> mapQueryResultRows(
  List<String> columns,
  List<List<dynamic>> rows,
) {
  return List<Map<String, dynamic>>.generate(
    rows.length,
    (index) => mapOdbcRowToStreamingMap(columns, rows[index]),
    growable: false,
  );
}
