import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/codecs/rpc_stream_columnar_chunk_codec.dart';

void main() {
  test('published columnar fixture comes from the production typed encoder', () {
    final result = toTypedColumnar(
      const QueryResult(
        columns: ['id', 'large', 'amount', 'name', 'optional'],
        rows: [
          [1, 1234567890123, 1.25, 'ação 🎉', null],
          [2, 1234567890124, 2.5, '漢字', 'present'],
        ],
        rowCount: 2,
      ),
    );
    final fixture = {
      'chunk': {
        'stream_id': 'fixture-columnar',
        'request_id': 'fixture-request',
        'chunk_index': 0,
        'rows': <Object>[],
        'columnar': RpcStreamColumnarChunkCodec.encodeTypedColumnarResult(result),
      },
      'expected_rows': RpcStreamColumnarChunkCodec.encodeRowMapsFromColumnar(result),
    };
    final file = File('test/fixtures/rpc/columnar_codec_fixture.json');
    if (Platform.environment['GENERATE_COMMUNICATION_FIXTURES'] == '1') {
      file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(fixture)}\n');
    }
    expect(jsonDecode(file.readAsStringSync()), jsonDecode(jsonEncode(fixture)));
  });
}
