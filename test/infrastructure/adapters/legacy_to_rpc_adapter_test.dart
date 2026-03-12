import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/adapters/legacy_to_rpc_adapter.dart';
import 'package:plug_agente/infrastructure/models/envelope_model.dart';

void main() {
  group('LegacyToRpcAdapter', () {
    test('should convert legacy envelope to RPC request', () {
      final envelope = EnvelopeModel(
        v: 1,
        type: 'query_request',
        requestId: 'req-123',
        agentId: 'agent-1',
        timestamp: DateTime.now(),
        cmp: 'none',
        contentType: 'json',
        payloadBytes: [
          {
            'query': 'SELECT * FROM users',
            'parameters': {'id': 1},
          },
        ],
      );

      final rpcRequest = LegacyToRpcAdapter.envelopeToRpcRequest(envelope);

      expect(rpcRequest.jsonrpc, equals('2.0'));
      expect(rpcRequest.method, equals('sql.execute'));
      expect(rpcRequest.id, equals('req-123'));
      expect(rpcRequest.params, isA<Map<String, dynamic>>());

      final params = rpcRequest.params as Map<String, dynamic>;
      expect(params['sql'], equals('SELECT * FROM users'));
      expect(params['params'], equals({'id': 1}));
    });

    test('should convert QueryRequest to RPC request', () {
      final queryRequest = QueryRequest(
        id: 'req-123',
        agentId: 'agent-1',
        query: 'SELECT * FROM users',
        parameters: {'id': 1},
        timestamp: DateTime.now(),
      );

      final rpcRequest = LegacyToRpcAdapter.queryRequestToRpcRequest(
        queryRequest,
      );

      expect(rpcRequest.jsonrpc, equals('2.0'));
      expect(rpcRequest.method, equals('sql.execute'));
      expect(rpcRequest.id, equals('req-123'));

      final params = rpcRequest.params as Map<String, dynamic>;
      expect(params['sql'], equals('SELECT * FROM users'));
      expect(params['params'], equals({'id': 1}));
    });

    test('should convert RPC success response to QueryResponse', () {
      final rpcResponse = RpcResponse.success(
        id: 'req-123',
        result: {
          'execution_id': 'exec-456',
          'rows': [
            {'id': 1, 'name': 'John'},
          ],
          'row_count': 1,
          'affected_rows': 0,
        },
      );

      final queryResponse = LegacyToRpcAdapter.rpcResponseToQueryResponse(
        rpcResponse,
        'agent-1',
      );

      expect(queryResponse.requestId, equals('req-123'));
      expect(queryResponse.agentId, equals('agent-1'));
      expect(queryResponse.data, hasLength(1));
      expect(queryResponse.data.first['id'], equals(1));
      expect(queryResponse.error, isNull);
    });

    test('should convert RPC error response to QueryResponse with error', () {
      final rpcResponse = RpcResponse.error(
        id: 'req-123',
        error: const RpcError(
          code: -32102,
          message: 'SQL execution failed',
          data: {'detail': 'Syntax error'},
        ),
      );

      final queryResponse = LegacyToRpcAdapter.rpcResponseToQueryResponse(
        rpcResponse,
        'agent-1',
      );

      expect(queryResponse.requestId, equals('req-123'));
      expect(queryResponse.agentId, equals('agent-1'));
      expect(queryResponse.data, isEmpty);
      expect(queryResponse.error, equals('SQL execution failed'));
    });

    test('should convert RPC response to legacy envelope', () {
      final rpcResponse = RpcResponse.success(
        id: 'req-123',
        result: {
          'execution_id': 'exec-456',
          'rows': [
            {'id': 1, 'name': 'John'},
          ],
          'row_count': 1,
        },
      );

      final envelope = LegacyToRpcAdapter.rpcResponseToEnvelope(
        rpcResponse,
        'agent-1',
      );

      expect(envelope.requestId, equals('req-123'));
      expect(envelope.agentId, equals('agent-1'));
      expect(envelope.type, equals('query_response'));
      expect(envelope.cmp, equals('none'));
      expect(envelope.contentType, equals('json'));
    });

    test('should handle envelope with empty payloadBytes', () {
      final envelope = EnvelopeModel(
        v: 1,
        type: 'query_request',
        requestId: 'req-123',
        agentId: 'agent-1',
        timestamp: DateTime.now(),
        cmp: 'none',
        contentType: 'json',
        payloadBytes: [],
      );

      final rpcRequest = LegacyToRpcAdapter.envelopeToRpcRequest(envelope);

      expect(rpcRequest.params, isA<Map<String, dynamic>>());
      final params = rpcRequest.params as Map<String, dynamic>;
      expect(params['sql'], equals(''));
    });
  });
}
