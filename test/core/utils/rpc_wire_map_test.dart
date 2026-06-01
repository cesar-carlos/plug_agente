import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/rpc_wire_map.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

void main() {
  group('RpcWireMap', () {
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
