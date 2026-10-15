import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_emitter.dart';

class _ObservedValues extends ListBase<String?> {
  final visited = <int>{};
  @override
  int get length => 5;
  @override
  set length(int value) => throw UnsupportedError('Read only');
  @override
  String? operator [](int index) {
    visited.add(index);
    return index == 1 ? null : 'value_$index';
  }

  @override
  void operator []=(int index, String? value) => throw UnsupportedError('Read only');
}

void main() {
  late _ObservedValues values;
  late TypedColumnarResult result;
  setUp(() {
    values = _ObservedValues();
    result = TypedColumnarResult(
      columns: [
        TypedColumnObject<String>(name: 'value', kind: TypedColumnKind.string, values: values),
      ],
      rowCount: values.length,
    );
  });

  test('awaits consumer before reading the next batch and preserves rows', () async {
    final release = Completer<void>();
    final first = Completer<void>();
    final chunks = <List<Map<String, dynamic>>>[];
    final work = OdbcColumnarStreamChunkEmitter.emit(
      result: result,
      fetchSize: 2,
      onChunk: (chunk) async {
        chunks.add(chunk);
        if (chunks.length == 1) {
          first.complete();
          await release.future;
        }
      },
    );
    await first.future;
    try {
      expect(values.visited, {0, 1});
    } finally {
      release.complete();
      await work;
    }
    expect(chunks, [
      [
        {'value': 'value_0'},
        {'value': null},
      ],
      [
        {'value': 'value_2'},
        {'value': 'value_3'},
      ],
      [
        {'value': 'value_4'},
      ],
    ]);
  });

  test('cancellation after delivery avoids mapping undispatched rows', () async {
    var cancelled = false;
    await OdbcColumnarStreamChunkEmitter.emit(
      result: result,
      fetchSize: 2,
      onChunk: (_) async {
        cancelled = true;
      },
      isCancelRequested: () => cancelled,
    );
    expect(values.visited, {0, 1});
  });

  test('consumer failure propagates without mapping the remaining batches', () async {
    final error = StateError('consumer failed');
    await expectLater(
      OdbcColumnarStreamChunkEmitter.emit(result: result, fetchSize: 2, onChunk: (_) async => throw error),
      throwsA(same(error)),
    );
    expect(values.visited, {0, 1});
  });

  test('wire delivery does not read object cells or call row consumer', () async {
    await OdbcColumnarStreamChunkEmitter.emit(
      result: result,
      fetchSize: 2,
      onChunk: (_) async => fail('Unexpected row materialization'),
      includeColumnarWire: true,
      onWireChunk: (chunk) async {
        expect(chunk.columnar!['row_count'], 5);
      },
    );
    expect(values.visited, isEmpty);
  });

  test('nonpositive fetch size retains default batch sizing', () async {
    final sizes = <int>[];
    await OdbcColumnarStreamChunkEmitter.emit(
      result: result,
      fetchSize: 0,
      onChunk: (chunk) async => sizes.add(chunk.length),
    );
    expect(sizes, [5]);
  });

  test('multiple batches preserve growable lists for existing consumers', () async {
    var count = 0;
    await OdbcColumnarStreamChunkEmitter.emit(
      result: result,
      fetchSize: 2,
      onChunk: (chunk) async {
        count++;
        chunk.add({'value': 'consumer'});
        expect(chunk.removeLast(), {'value': 'consumer'});
      },
    );
    expect(count, 3);
  });

  test('single batch preserves its fixed list size', () async {
    await OdbcColumnarStreamChunkEmitter.emit(
      result: result,
      fetchSize: 10,
      onChunk: (chunk) async {
        expect(() => chunk.add({'value': 'consumer'}), throwsUnsupportedError);
      },
    );
  });
}
