import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_batch.dart';
import 'package:plug_agente/domain/protocol/rpc_request.dart';

void main() {
  group('RpcBatchRequest.validateStrict', () {
    test('should return valid when batch has unique IDs', () {
      const batch = RpcBatchRequest([
        RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'r-1',
          params: <String, dynamic>{},
        ),
        RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'r-2',
          params: <String, dynamic>{},
        ),
      ]);

      final result = batch.validateStrict();

      expect(result, isA<RpcBatchValid>());
    });

    test('should return duplicateIds when batch has duplicate IDs', () {
      const batch = RpcBatchRequest([
        RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'r-1',
          params: <String, dynamic>{},
        ),
        RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'r-1',
          params: <String, dynamic>{},
        ),
      ]);

      final result = batch.validateStrict();

      expect(result, isA<RpcBatchDuplicateIds>());
      final dup = result as RpcBatchDuplicateIds;
      expect(dup.duplicateIds, contains('r-1'));
    });

    test('should return exceedsLimit when batch size exceeds max', () {
      final requests = List.generate(
        rpcBatchMaxSize + 1,
        (i) => RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'r-$i',
          params: <String, dynamic>{},
        ),
      );
      final batch = RpcBatchRequest(requests);

      final result = batch.validateStrict();

      expect(result, isA<RpcBatchExceedsLimit>());
      final exc = result as RpcBatchExceedsLimit;
      expect(exc.size, equals(rpcBatchMaxSize + 1));
      expect(exc.limit, equals(rpcBatchMaxSize));
    });

    test('should allow notifications (null id) in batch', () {
      const batch = RpcBatchRequest([
        RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'r-1',
          params: <String, dynamic>{},
        ),
        RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: null,
          params: <String, dynamic>{},
        ),
      ]);

      final result = batch.validateStrict();

      expect(result, isA<RpcBatchValid>());
    });
  });
}
