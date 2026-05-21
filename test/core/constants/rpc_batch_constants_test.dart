import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/rpc_batch_constants.dart';

void main() {
  group('RpcBatchConstants', () {
    test('batch diagnostic strings should be non-empty and distinct', () {
      final values = <String>[
        RpcBatchConstants.duplicateRequestIdsReason,
        RpcBatchConstants.exceedsLimitReason,
        RpcBatchConstants.duplicateRequestIdsTechnicalMessagePrefix,
        RpcBatchConstants.exceedsLimitTechnicalMessagePrefix,
      ];
      expect(values, everyElement(isNotEmpty));
      expect(values.toSet().length, values.length);
    });
  });
}
