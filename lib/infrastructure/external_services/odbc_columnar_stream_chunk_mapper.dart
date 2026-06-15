import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_chunk_mapper.dart';

export 'package:plug_agente/domain/streaming/streaming_column_metadata.dart';

/// Input for mapping a native columnar ODBC chunk to Hub row-map chunks.
final class OdbcColumnarStreamChunkMapperInput {
  const OdbcColumnarStreamChunkMapperInput({
    required this.result,
    required this.fetchSize,
  });

  final TypedColumnarResult result;
  final int fetchSize;
}

/// Normalizes object-column cells for Hub row-map streaming.
///
/// SQL Anywhere may surface TIMESTAMP/DATE as text while the column is still
/// tagged as [TypedColumnKind.dateTime]; pass text through like row-major SELECT.
Object? normalizeTypedColumnarObjectCell(TypedColumnKind kind, Object? value) {
  if (value == null) {
    return null;
  }
  if (kind == TypedColumnKind.dateTime && value is! DateTime) {
    return value;
  }
  return value;
}

/// Reads one cell from a typed columnar column without materializing row-major
/// [QueryResult] first.
Object? readTypedColumnarCell(TypedColumn column, int row) {
  if (column.isNullAt(row)) {
    return null;
  }
  return switch (column) {
    TypedColumnInt32(:final values) => values[row],
    TypedColumnInt64(:final values) => values[row],
    TypedColumnFloat64(:final values) => values[row],
    TypedColumnObject(:final kind, :final values) => normalizeTypedColumnarObjectCell(
      kind,
      values[row],
    ),
  };
}

Map<String, dynamic> mapTypedColumnarRow(
  List<TypedColumn> columns,
  int row,
) {
  final mappedRow = <String, dynamic>{};
  for (final column in columns) {
    mappedRow[column.name] = readTypedColumnarCell(column, row);
  }
  return mappedRow;
}

/// Maps a [TypedColumnarResult] chunk into Hub row-map wire chunks.
List<List<Map<String, dynamic>>> mapTypedColumnarToChunks(
  OdbcColumnarStreamChunkMapperInput input,
) {
  final rowCount = input.result.rowCount;
  if (rowCount <= 0) {
    return const <List<Map<String, dynamic>>>[];
  }

  final columns = input.result.columns;
  final safeFetchSize = effectiveStreamingFetchSize(input.fetchSize);
  if (shouldSkipRechunk(rowCount, safeFetchSize)) {
    return <List<Map<String, dynamic>>>[
      mapTypedColumnarToRowMaps(input.result),
    ];
  }

  final chunks = <List<Map<String, dynamic>>>[];
  var chunk = <Map<String, dynamic>>[];

  for (var row = 0; row < rowCount; row++) {
    chunk.add(mapTypedColumnarRow(columns, row));
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

/// Maps every row in a columnar chunk to the Hub row-map shape.
List<Map<String, dynamic>> mapTypedColumnarToRowMaps(TypedColumnarResult result) {
  final rowCount = result.rowCount;
  if (rowCount <= 0) {
    return const <Map<String, dynamic>>[];
  }

  final columns = result.columns;
  return List<Map<String, dynamic>>.generate(
    rowCount,
    (row) => mapTypedColumnarRow(columns, row),
    growable: false,
  );
}

/// Column metadata for the first streaming chunk when native metadata is present.
List<Map<String, dynamic>>? buildStreamingColumnMetadata(TypedColumnarResult result) {
  final names = result.columns.map((column) => column.name).toList(growable: false);
  if (names.isEmpty) {
    return null;
  }
  return names.map((name) => <String, dynamic>{'name': name}).toList(growable: false);
}
