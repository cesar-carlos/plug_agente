import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';

void main() {
  const validator = RpcContractValidator();

  group('RpcContractValidator validateResponse meta', () {
    test('should reject invalid meta.traceparent', () {
      final result = validator.validateResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': '1',
        'result': <String, dynamic>{},
        'meta': <String, dynamic>{
          'traceparent': 'not-w3c-format',
        },
      });

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull().toString(), contains('traceparent'));
    });

    test('should reject invalid meta.tracestate', () {
      final result = validator.validateResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': '1',
        'result': <String, dynamic>{},
        'meta': <String, dynamic>{
          'tracestate': 'a' * 600,
        },
      });

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull().toString(), contains('tracestate'));
    });

    test('should reject non-object meta', () {
      final result = validator.validateResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': '1',
        'result': <String, dynamic>{},
        'meta': 'oops',
      });

      expect(result.isError(), isTrue);
    });
  });

  group('RpcContractValidator validateBatchResponse', () {
    test('should reject empty batch', () {
      final result = validator.validateBatchResponse(<dynamic>[]);
      expect(result.isError(), isTrue);
    });

    test('should reject non-object batch item', () {
      final result = validator.validateBatchResponse(<dynamic>[1]);
      expect(result.isError(), isTrue);
    });
  });

  group('RpcContractValidator validateStreamChunk', () {
    test('should reject missing stream_id', () {
      final result = validator.validateStreamChunk(<String, dynamic>{
        'chunk_index': 0,
        'rows': <dynamic>[],
      });
      expect(result.isError(), isTrue);
    });

    test('should reject negative chunk_index', () {
      final result = validator.validateStreamChunk(<String, dynamic>{
        'stream_id': 's1',
        'chunk_index': -1,
        'rows': <dynamic>[],
      });
      expect(result.isError(), isTrue);
    });

    test('should reject rows that are not all objects', () {
      final result = validator.validateStreamChunk(<String, dynamic>{
        'stream_id': 's1',
        'chunk_index': 0,
        'rows': <dynamic>[1],
      });
      expect(result.isError(), isTrue);
    });

    test('should reject invalid total_chunks', () {
      final result = validator.validateStreamChunk(<String, dynamic>{
        'stream_id': 's1',
        'chunk_index': 0,
        'rows': <dynamic>[],
        'total_chunks': 0,
      });
      expect(result.isError(), isTrue);
    });

    test('should reject invalid column_metadata', () {
      final result = validator.validateStreamChunk(<String, dynamic>{
        'stream_id': 's1',
        'chunk_index': 0,
        'rows': <dynamic>[],
        'column_metadata': <dynamic>[1],
      });
      expect(result.isError(), isTrue);
    });
  });

  group('RpcContractValidator validateAgentRegister', () {
    test('should reject empty agentId', () {
      final result = validator.validateAgentRegister(<String, dynamic>{
        'agentId': '   ',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'capabilities': ProtocolCapabilities.defaultCapabilities().toJson(),
      });
      expect(result.isError(), isTrue);
    });

    test('should reject invalid timestamp', () {
      final result = validator.validateAgentRegister(<String, dynamic>{
        'agentId': 'a1',
        'timestamp': 'not-a-date',
        'capabilities': ProtocolCapabilities.defaultCapabilities().toJson(),
      });
      expect(result.isError(), isTrue);
    });

    test('should reject non-map capabilities', () {
      final result = validator.validateAgentRegister(<String, dynamic>{
        'agentId': 'a1',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'capabilities': 'x',
      });
      expect(result.isError(), isTrue);
    });
  });

  group('RpcContractValidator validateAgentCapabilitiesEnvelope', () {
    test('should reject missing capabilities object', () {
      final result = validator.validateAgentCapabilitiesEnvelope(<String, dynamic>{});
      expect(result.isError(), isTrue);
    });
  });

  group('RpcContractValidator validateResponse result fields', () {
    test('should reject invalid pagination.page', () {
      final result = validator.validateResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': '1',
        'result': <String, dynamic>{
          'pagination': <String, dynamic>{
            'page': 0,
            'page_size': 10,
            'returned_rows': 5,
            'has_next_page': false,
            'has_previous_page': false,
          },
        },
      });
      expect(result.isError(), isTrue);
    });

    test('should reject invalid pagination.has_next_page type', () {
      final result = validator.validateResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': '1',
        'result': <String, dynamic>{
          'pagination': <String, dynamic>{
            'page': 1,
            'page_size': 10,
            'returned_rows': 5,
            'has_next_page': 'no',
            'has_previous_page': false,
          },
        },
      });
      expect(result.isError(), isTrue);
    });

    test('should reject invalid result_sets item', () {
      final result = validator.validateResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': '1',
        'result': <String, dynamic>{
          'result_sets': <dynamic>[
            <String, dynamic>{
              'index': -1,
              'rows': <dynamic>[],
            },
          ],
        },
      });
      expect(result.isError(), isTrue);
    });

    test('should accept row_count item with only required fields', () {
      final result = validator.validateResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': '1',
        'result': <String, dynamic>{
          'items': <dynamic>[
            <String, dynamic>{
              'type': 'row_count',
              'index': 0,
            },
          ],
        },
      });
      expect(result.isSuccess(), isTrue);
    });

    test('should reject row_count item with negative affected_rows', () {
      final result = validator.validateResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': '1',
        'result': <String, dynamic>{
          'items': <dynamic>[
            <String, dynamic>{
              'type': 'row_count',
              'index': 0,
              'affected_rows': -1,
            },
          ],
        },
      });
      expect(result.isError(), isTrue);
    });
  });

  group('RpcContractValidator validateResponse error envelope', () {
    test('should reject error missing message', () {
      final result = validator.validateResponse(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': '1',
        'error': <String, dynamic>{
          'code': 1,
        },
      });
      expect(result.isError(), isTrue);
    });
  });
}
