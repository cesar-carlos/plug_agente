import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';

void main() {
  const validator = RpcContractValidator();

  group('RpcContractValidator sql.executeBatch result items', () {
    test('should accept batch items with ok and snake_case counters', () {
      final payload = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'b1',
        'result': {
          'execution_id': 'e1',
          'started_at': '2026-01-01T00:00:00Z',
          'finished_at': '2026-01-01T00:00:01Z',
          'items': [
            {
              'index': 0,
              'ok': true,
              'rows': [
                {'id': 1},
              ],
              'row_count': 1,
            },
            {
              'index': 1,
              'ok': false,
              'error': 'boom',
            },
          ],
          'total_commands': 2,
          'successful_commands': 1,
          'failed_commands': 1,
        },
      };

      final result = validator.validateResponse(payload);
      expect(result.isSuccess(), isTrue);
    });
  });

  group('RpcContractValidator sql.execute multi-result items', () {
    test('should accept multi-result items with type result_set', () {
      final payload = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'r1',
        'result': {
          'execution_id': 'e1',
          'started_at': '2026-01-01T00:00:00Z',
          'finished_at': '2026-01-01T00:00:01Z',
          'rows': [
            {'a': 1},
          ],
          'row_count': 1,
          'items': [
            {
              'type': 'result_set',
              'index': 0,
              'result_set_index': 0,
              'rows': [
                {'a': 1},
              ],
              'row_count': 1,
            },
          ],
        },
      };

      final result = validator.validateResponse(payload);
      expect(result.isSuccess(), isTrue);
    });
  });
}
