import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/rpc_batch_constants.dart';
import 'package:plug_agente/core/constants/rpc_batch_negotiation.dart';

void main() {
  group('ParallelBatchDispatchNegotiation', () {
    test('should parse boolean negotiated extension', () {
      final parsed = ParallelBatchDispatchNegotiation.fromNegotiatedExtensions(
        const {'parallelBatchDispatch': true},
      );

      expect(parsed, isNotNull);
      expect(parsed!.enabled, isTrue);
      expect(parsed.maxConcurrency, RpcBatchConstants.maxParallelJsonRpcBatchDispatchConcurrency);
      expect(parsed.mixedReadOnlyMethods, isTrue);
      expect(parsed.selectOnlySqlExecute, isTrue);
    });

    test('should parse structured negotiated extension', () {
      final parsed = ParallelBatchDispatchNegotiation.fromNegotiatedExtensions(
        const {
          'parallelBatchDispatch': {
            'enabled': true,
            'maxConcurrency': 2,
            'mixedReadOnlyMethods': true,
            'selectOnlySqlExecute': false,
          },
        },
      );

      expect(parsed, isNotNull);
      expect(parsed!.maxConcurrency, 2);
      expect(parsed.mixedReadOnlyMethods, isTrue);
      expect(parsed.selectOnlySqlExecute, isFalse);
    });

    test('should return null when extension is disabled', () {
      final parsed = ParallelBatchDispatchNegotiation.fromNegotiatedExtensions(
        const {
          'parallelBatchDispatch': {
            'enabled': false,
          },
        },
      );

      expect(parsed, isNull);
    });
  });
}
