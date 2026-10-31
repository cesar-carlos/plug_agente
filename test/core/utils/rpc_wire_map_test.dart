import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/rpc_wire_map.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

void main() {
  test('preserves the terminal catalog cursor and an unspecified stream description', () {
    final result = <String, dynamic>{
      'next_cursor': null,
      'actions': [{'action_id': 'a', 'stdin_description': null}],
    };
    final response = RpcResponse.success(id: 'catalog', result: result);
    expect(RpcWireMap.sanitizeRpcResponse(response).result, result);
    expect((RpcWireMap.sanitizeRpcResponseWirePayload([response.toJson()]) as List).single, response.toJson());
  });
  test('preserves null exit code in persisted I/O events through every wire sanitation path', () {
    final result = <String, dynamic>{
      'execution_id': 'execution',
      'next_sequence': 2,
      'terminal': true,
      'output_complete': true,
      'events': [
        {'sequence': 1, 'type': 'process_exited', 'exit_code': null},
        {'sequence': 2, 'type': 'completed', 'output_complete': true},
      ],
    };
    final response = RpcResponse.success(id: 'page', result: result);
    expect(RpcWireMap.sanitizeRpcResponse(response).result, result);
    expect((RpcWireMap.sanitizeRpcResponseWirePayload(response.toJson()) as Map)['result'], result);
    expect((RpcWireMap.sanitizeRpcResponseWirePayload([response.toJson()]) as List).single, response.toJson());
  });
  test('preserves required null execution identity for unsuccessful I/O lookup', () {
    final result = <String, dynamic>{'found': false, 'execution_id': null, 'reason': 'not_found_in_retention_window'};
    final response = RpcResponse.success(id: 'lookup', result: result);
    expect(RpcWireMap.sanitizeRpcResponse(response).result, result);
    expect((RpcWireMap.sanitizeRpcResponseWirePayload(response.toJson()) as Map)['result'], result);
    expect((RpcWireMap.sanitizeRpcResponseWirePayload([response.toJson()]) as List).single, response.toJson());
  });
  test('preserves unknown confirmed byte count in I/O receipts on the wire', () {
    final result = <String, dynamic>{
      'execution_id': 'execution',
      'message_id': 'input',
      'sequence': 0,
      'state': 'unknown',
      'confirmed_bytes': null,
      'next_input_sequence': 1,
      'stdin_state': 'failed',
    };
    final wire =
        RpcWireMap.sanitizeRpcResponseWirePayload(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': 'receipt',
              'result': result,
            })
            as Map<String, dynamic>;
    expect(wire['result'], result);
    final batch = RpcWireMap.sanitizeRpcResponseWirePayload([wire]) as List<dynamic>;
    expect((batch.single as Map)['result'], result);
    expect(RpcWireMap.sanitizeRpcResponse(RpcResponse.success(id: 'receipt', result: result)).result, result);
  });
  group('RpcWireMap', () {
    test('native SQL envelopes preserve null cells in every result set', () {
      final rows = [
        <String, dynamic>{'id': 1, 'marker': null},
      ];
      final set = <String, dynamic>{'row_count': 1, 'rows': rows, 'affected_rows': null};
      final response = RpcResponse.success(
        id: 'multi',
        result: <String, dynamic>{
          ...set,
          'multi_result': true,
          'result_sets': [set],
          'items': [set],
        },
      );
      final result = RpcWireMap.sanitizeRpcResponse(response).result as Map;
      expect(result['rows'], rows);
      for (final key in ['result_sets', 'items']) {
        final item = (result[key] as List).single as Map;
        expect(item['rows'], rows);
        expect(item.containsKey('affected_rows'), isFalse);
      }
    });
    test('SQL cells retain null and column positions through wire, batch and replay', () {
      for (final rows in <List<dynamic>>[
        [
          <String, dynamic>{'id': 1, 'marker': null},
        ],
        [
          <dynamic>[1, null],
        ],
      ]) {
        final response = RpcResponse.success(
          id: 'sql',
          result: <String, dynamic>{
            'columns': ['id', 'marker'],
            'rows': rows,
            'affected_rows': null,
          },
        );
        final replay = RpcWireMap.sanitizeRpcResponse(response).result as Map;
        final wire = (RpcWireMap.sanitizeRpcResponseWirePayload(response.toJson()) as Map)['result'] as Map;
        final batch = (RpcWireMap.sanitizeRpcResponseWirePayload([response.toJson()]) as List).single as Map;
        for (final result in [replay, wire, batch['result'] as Map]) {
          expect(result['rows'], rows);
          expect(result.containsKey('affected_rows'), isFalse);
        }
      }
    });
    test('preserves required null journal counts through wire, batch and replay sanitation', () {
      final result = <String, dynamic>{'operationId': 'operation', 'directlyAffectedRows': null};
      final response = RpcResponse.success(id: 'request', result: result);
      expect(RpcWireMap.sanitizeRpcResponse(response).result, result);
      expect((RpcWireMap.sanitizeRpcResponseWirePayload(response.toJson()) as Map)['result'], result);
      expect((RpcWireMap.sanitizeRpcResponseWirePayload([response.toJson()]) as List).single, response.toJson());
    });
    test('putOptionalInt omits null values', () {
      final map = <String, dynamic>{'row_count': 0};
      RpcWireMap.putOptionalInt(map, 'affected_rows', null);
      expect(map.containsKey('affected_rows'), isFalse);
      RpcWireMap.putOptionalInt(map, 'affected_rows', 3);
      expect(map['affected_rows'], 3);
    });

    test('omitNullEntriesDeep removes nulls from nested maps and lists', () {
      final sanitized = RpcWireMap.omitNullEntriesDeep(<String, dynamic>{
        'affected_rows': null,
        'items': [
          <String, dynamic>{'affected_rows': null, 'row_count': 1},
        ],
        'pagination': <String, dynamic>{'next_cursor': null, 'page': 1},
      });

      expect(sanitized.containsKey('affected_rows'), isFalse);
      final items = sanitized['items'] as List<dynamic>;
      expect((items.first as Map<String, dynamic>).containsKey('affected_rows'), isFalse);
      expect((items.first as Map<String, dynamic>)['row_count'], 1);
      final pagination = sanitized['pagination'] as Map<String, dynamic>;
      expect(pagination.containsKey('next_cursor'), isFalse);
      expect(pagination['page'], 1);
    });

    test('sanitizeRpcResponseWirePayload strips null result fields', () {
      final wire = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'req-1',
        'result': <String, dynamic>{
          'execution_id': 'exec-1',
          'affected_rows': null,
        },
      };

      final sanitized = RpcWireMap.sanitizeRpcResponseWirePayload(wire) as Map<String, dynamic>;
      final result = sanitized['result'] as Map<String, dynamic>;
      expect(result.containsKey('affected_rows'), isFalse);
    });

    test('sanitizeRpcResponse strips null fields from RpcResponse result', () {
      final response = RpcResponse.success(
        id: 'req-1',
        result: <String, dynamic>{
          'execution_id': 'exec-1',
          'affected_rows': null,
        },
      );

      final sanitized = RpcWireMap.sanitizeRpcResponse(response);
      final result = sanitized.result as Map<String, dynamic>;
      expect(result.containsKey('affected_rows'), isFalse);
    });
  });
}
