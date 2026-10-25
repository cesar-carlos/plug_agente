import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_mapper.dart';

void main() {
  test('metadata mapping preserves empty, duplicate and unicode names', () {
    for (final names in <List<String>>[
      [],
      ['id'],
      ['id', 'ação', 'id', ''],
    ]) {
      final result = TypedColumnarResult(
        columns: [
          for (final name in names) TypedColumnObject<String>(name: name, kind: TypedColumnKind.string, values: []),
        ],
        rowCount: 0,
      );
      expect(
        buildStreamingColumnMetadata(result),
        names.isEmpty
            ? null
            : [
                for (final name in names) {'name': name},
              ],
      );
    }
  });

  test('metadata mapping returns independent maps and does not alter input', () {
    final result = TypedColumnarResult(
      columns: [
        for (var i = 0; i < 2; i++) TypedColumnObject<String>(name: 'id', kind: TypedColumnKind.string, values: []),
      ],
      rowCount: 0,
    );
    final metadata = buildStreamingColumnMetadata(result)!;
    metadata.first['name'] = 'changed';
    expect(metadata[1]['name'], 'id');
    expect(result.columns.first.name, 'id');
    expect(buildStreamingColumnMetadata(result)!.first['name'], 'id');
  });
}
