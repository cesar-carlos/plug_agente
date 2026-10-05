import 'package:plug_agente/core/utils/odbc_wire_cell_normalizer.dart';

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
Object? normalizeOdbcStreamingCell(Object? value) => normalizeOdbcWireCell(value);

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
  final safeFetchSize = effectiveStreamingFetchSize(fetchSize);
  for (var start = 0; start < rows.length; start += safeFetchSize) {
    if (isCancelRequested?.call() ?? false) return;
    final remaining = rows.length - start;
    final length = remaining < safeFetchSize ? remaining : safeFetchSize;
    final chunk = List<Map<String, dynamic>>.generate(
      length,
      (index) => mapOdbcRowToStreamingMap(columns, rows[start + index]),
      growable: false,
    );
    await onChunk(chunk);
    if (isCancelRequested?.call() ?? false) return;
    if (rows.length > safeFetchSize) await Future<void>.delayed(Duration.zero);
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
      chunks.add(chunk);
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
