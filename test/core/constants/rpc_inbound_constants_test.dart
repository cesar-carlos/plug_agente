import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_inbound_constants.dart';

void main() {
  group('RpcInboundConstants', () {
    test('concurrentHandlersExceededTechnicalMessage should embed the configured cap', () {
      expect(
        RpcInboundConstants.concurrentHandlersExceededTechnicalMessage(
          ConnectionConstants.maxConcurrentRpcHandlers,
        ),
        'Concurrent RPC handler limit exceeded (${ConnectionConstants.maxConcurrentRpcHandlers})',
      );
    });

    test('inbound diagnostic strings should be non-empty and distinct', () {
      final reasons = <String>[
        RpcInboundConstants.protocolNotReadyReason,
        RpcInboundConstants.concurrentHandlersExceededReason,
        RpcInboundConstants.rateWindowExceededReason,
        RpcInboundConstants.unhandledExceptionFailureCode,
        RpcInboundConstants.unhandledBatchExceptionFailureCode,
        RpcInboundConstants.unhandledSingleRequestTechnicalMessage,
        RpcInboundConstants.unhandledBatchProcessingTechnicalMessage,
        RpcInboundConstants.batchRequestEmptyDetail,
        RpcInboundConstants.protocolNotReadyTechnicalMessage,
        RpcInboundConstants.requestMustBeJsonObjectTechnicalMessage,
        RpcInboundConstants.requestExceedsPayloadLimitTechnicalMessage,
        RpcInboundConstants.batchRequestExceedsPayloadLimitTechnicalMessage,
        RpcInboundConstants.eachBatchElementMustBeJsonObjectTechnicalMessage,
        RpcInboundConstants.invalidPayloadSignatureTechnicalMessage,
        RpcInboundConstants.nullIdNotificationsCompatibilityTechnicalMessage,
        RpcInboundConstants.unexpectedGuardResultTechnicalMessage,
        RpcInboundConstants.rateLimitExceededForRpcRequestTechnicalMessage,
        RpcInboundConstants.duplicateRequestIdWithinReplayWindowTechnicalMessage,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
