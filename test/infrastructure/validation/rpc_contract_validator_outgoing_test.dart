import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
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

    test('should accept multi_result envelope with result_sets array', () {
      final payload = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'mr1',
        'result': {
          'execution_id': 'e1',
          'started_at': '2026-01-01T00:00:00Z',
          'finished_at': '2026-01-01T00:00:01Z',
          'multi_result': true,
          'result_set_count': 2,
          'item_count': 2,
          'rows': <Map<String, dynamic>>[],
          'row_count': 0,
          'result_sets': [
            {
              'index': 0,
              'rows': [
                {'id': 1},
              ],
              'row_count': 1,
            },
            {
              'index': 1,
              'rows': [
                {'row_count': 3},
              ],
              'row_count': 1,
            },
          ],
        },
      };

      expect(validator.validateResponse(payload).isSuccess(), isTrue);
    });

    test('should accept items mixing result_set and row_count', () {
      final payload = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'mr2',
        'result': {
          'execution_id': 'e1',
          'started_at': '2026-01-01T00:00:00Z',
          'finished_at': '2026-01-01T00:00:01Z',
          'multi_result': true,
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
            {
              'type': 'row_count',
              'index': 1,
              'affected_rows': 2,
            },
          ],
        },
      };

      expect(validator.validateResponse(payload).isSuccess(), isTrue);
    });

    test('should reject multi_result when not a boolean', () {
      final payload = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'mr3',
        'result': {
          'execution_id': 'e1',
          'started_at': '2026-01-01T00:00:00Z',
          'finished_at': '2026-01-01T00:00:01Z',
          'multi_result': 'true',
          'rows': <Map<String, dynamic>>[],
          'row_count': 0,
        },
      };

      expect(validator.validateResponse(payload).isError(), isTrue);
    });

    test('should reject result_sets when not an array', () {
      final payload = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'mr4',
        'result': {
          'execution_id': 'e1',
          'started_at': '2026-01-01T00:00:00Z',
          'finished_at': '2026-01-01T00:00:01Z',
          'multi_result': true,
          'rows': <Map<String, dynamic>>[],
          'row_count': 0,
          'result_sets': <String, dynamic>{},
        },
      };

      expect(validator.validateResponse(payload).isError(), isTrue);
    });

    test('should reject result_sets entry with non-object rows', () {
      final payload = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'mr5',
        'result': {
          'execution_id': 'e1',
          'started_at': '2026-01-01T00:00:00Z',
          'finished_at': '2026-01-01T00:00:01Z',
          'multi_result': true,
          'rows': <Map<String, dynamic>>[],
          'row_count': 0,
          'result_sets': [
            {
              'index': 0,
              'rows': [1, 2, 3],
              'row_count': 3,
            },
          ],
        },
      };

      expect(validator.validateResponse(payload).isError(), isTrue);
    });

    test(
      'should reject when result_set_count does not match result_sets length',
      () {
        final payload = <String, dynamic>{
          'jsonrpc': '2.0',
          'id': 'mr6',
          'result': {
            'execution_id': 'e1',
            'started_at': '2026-01-01T00:00:00Z',
            'finished_at': '2026-01-01T00:00:01Z',
            'multi_result': true,
            'result_set_count': 9,
            'rows': <Map<String, dynamic>>[],
            'row_count': 0,
            'result_sets': [
              {
                'index': 0,
                'rows': <Map<String, dynamic>>[],
                'row_count': 0,
              },
            ],
          },
        };

        expect(validator.validateResponse(payload).isError(), isTrue);
      },
    );

    test('should reject when item_count does not match items length', () {
      final payload = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'mr7',
        'result': {
          'execution_id': 'e1',
          'started_at': '2026-01-01T00:00:00Z',
          'finished_at': '2026-01-01T00:00:01Z',
          'item_count': 99,
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

      expect(validator.validateResponse(payload).isError(), isTrue);
    });
  });

  group('validateRowElementTypes fast path', () {
    test('should accept non-map row entries when validateRowElementTypes is false',
        () {
      final payload = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 1,
        'result': <String, dynamic>{
          'rows': <dynamic>[1, 2, 3],
          'row_count': 3,
        },
      };
      expect(
        validator.validateResponse(
          payload,
          validateRowElementTypes: false,
        ).isSuccess(),
        isTrue,
      );
      expect(validator.validateResponse(payload).isError(), isTrue);
    });

    test('validateStreamChunk skips row map check when false', () {
      final chunk = <String, dynamic>{
        'stream_id': 's1',
        'request_id': 'r1',
        'chunk_index': 0,
        'rows': <dynamic>['not-a-map'],
      };
      expect(
        validator.validateStreamChunk(
          chunk,
          validateRowElementTypes: false,
        ).isSuccess(),
        isTrue,
      );
      expect(validator.validateStreamChunk(chunk).isError(), isTrue);
    });
  });

  group('RpcContractValidator rpc:complete (validateStreamComplete)', () {
    test('should accept optional terminal_status aborted', () {
      final result = validator.validateStreamComplete(<String, dynamic>{
        'stream_id': 's1',
        'request_id': '1',
        'total_rows': 0,
        'terminal_status': 'aborted',
      });
      expect(result.isSuccess(), isTrue);
    });

    test('should accept optional terminal_status error', () {
      final result = validator.validateStreamComplete(<String, dynamic>{
        'stream_id': 's1',
        'request_id': '1',
        'total_rows': 3,
        'terminal_status': 'error',
      });
      expect(result.isSuccess(), isTrue);
    });

    test('should reject invalid terminal_status', () {
      final result = validator.validateStreamComplete(<String, dynamic>{
        'stream_id': 's1',
        'request_id': '1',
        'total_rows': 0,
        'terminal_status': 'invalid',
      });
      expect(result.isError(), isTrue);
    });
  });

  group('RpcContractValidator agent:register', () {
    test('should accept optional load with handler counts', () {
      final result = validator.validateAgentRegister(<String, dynamic>{
        'agentId': 'a1',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'capabilities': ProtocolCapabilities.defaultCapabilities().toJson(),
        'load': <String, int>{
          'active_handlers': 2,
          'max_handlers': 32,
        },
      });
      expect(result.isSuccess(), isTrue);
    });

    test('should reject load with invalid max_handlers', () {
      final result = validator.validateAgentRegister(<String, dynamic>{
        'agentId': 'a1',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'capabilities': ProtocolCapabilities.defaultCapabilities().toJson(),
        'load': <String, int>{
          'active_handlers': 0,
          'max_handlers': 0,
        },
      });
      expect(result.isError(), isTrue);
    });
  });
}
