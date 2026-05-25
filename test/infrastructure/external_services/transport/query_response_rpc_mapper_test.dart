import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/query_response_rpc_mapper.dart';

void main() {
  group('QueryResponseRpcMapper', () {
    final baseTimestamp = DateTime.utc(2026, 1, 15, 10);
    final startTimestamp = DateTime.utc(2026, 1, 15, 9, 59, 59);

    QueryResponse buildResponse({
      String? error,
      DateTime? startedAt,
      DateTime? timestamp,
      List<Map<String, dynamic>> data = const [],
    }) {
      return QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: data,
        timestamp: timestamp ?? baseTimestamp,
        startedAt: startedAt,
        error: error,
      );
    }

    group('toRpcResult', () {
      test('should use startedAt when available (H1)', () {
        final response = buildResponse(startedAt: startTimestamp);

        final result = QueryResponseRpcMapper.toRpcResult(response);

        expect(result['started_at'], startTimestamp.toIso8601String());
        expect(result['finished_at'], baseTimestamp.toIso8601String());
        expect(result['started_at'] != result['finished_at'], isTrue);
      });

      test('should fall back to timestamp when startedAt is null', () {
        final response = buildResponse();

        final result = QueryResponseRpcMapper.toRpcResult(response);

        expect(result['started_at'], baseTimestamp.toIso8601String());
        expect(result['finished_at'], baseTimestamp.toIso8601String());
      });

      test('should include row_count and rows', () {
        final rows = [
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'},
        ];
        final response = buildResponse(data: rows);

        final result = QueryResponseRpcMapper.toRpcResult(response);

        expect(result['row_count'], 2);
        expect(result['rows'], rows);
        expect(result['execution_id'], 'exec-1');
      });

      test('should omit optional fields when null', () {
        final response = buildResponse();

        final result = QueryResponseRpcMapper.toRpcResult(response);

        expect(result.containsKey('affected_rows'), isFalse);
        expect(result.containsKey('column_metadata'), isFalse);
        expect(result.containsKey('pagination'), isFalse);
        expect(result.containsKey('multi_result'), isFalse);
      });

      test('should include affected_rows when present', () {
        final response = QueryResponse(
          id: 'exec-2',
          requestId: 'req-2',
          agentId: 'agent-1',
          data: const [],
          timestamp: baseTimestamp,
          affectedRows: 42,
        );

        final result = QueryResponseRpcMapper.toRpcResult(response);

        expect(result['affected_rows'], 42);
      });
    });

    group('toRpcResponse', () {
      test('should return success RpcResponse for non-error response', () {
        final response = buildResponse(data: [
          {'col': 'value'},
        ]);

        final rpc = QueryResponseRpcMapper.toRpcResponse(response);

        expect(rpc.id, 'req-1');
        expect(rpc.error, isNull);
        expect(rpc.result, isNotNull);
        expect((rpc.result as Map<String, dynamic>)['rows'], hasLength(1));
      });

      test('should return error RpcResponse when error is set', () {
        final response = buildResponse(error: 'Column not found: foo');

        final rpc = QueryResponseRpcMapper.toRpcResponse(response);

        expect(rpc.id, 'req-1');
        expect(rpc.error, isNotNull);
        expect(rpc.error!.code, RpcErrorCode.sqlExecutionFailed);
        expect(rpc.result, isNull);
        final data = rpc.error!.data as Map<String, dynamic>;
        expect(data['technical_message'], contains('Column not found'));
      });
    });
  });
}
