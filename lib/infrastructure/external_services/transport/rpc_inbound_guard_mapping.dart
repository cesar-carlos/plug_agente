import 'package:plug_agente/core/constants/rpc_inbound_constants.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';

int rpcInboundGuardResultToCode(RpcRequestGuardResult result) {
  switch (result) {
    case RpcRequestGuardResult.allow:
      assert(false, 'guard.allow should not reach error mapping path');
      return RpcErrorCode.internalError;
    case RpcRequestGuardResult.rateLimited:
      return RpcErrorCode.rateLimited;
    case RpcRequestGuardResult.replayDetected:
      return RpcErrorCode.replayDetected;
  }
}

String? rpcInboundGuardResultToReason(RpcRequestGuardResult result) {
  switch (result) {
    case RpcRequestGuardResult.allow:
      return null;
    case RpcRequestGuardResult.rateLimited:
      return RpcInboundConstants.rateWindowExceededReason;
    case RpcRequestGuardResult.replayDetected:
      return RpcErrorCode.getReason(RpcErrorCode.replayDetected);
  }
}

String rpcInboundGuardResultToTechnicalMessage(RpcRequestGuardResult result) {
  switch (result) {
    case RpcRequestGuardResult.allow:
      return RpcInboundConstants.unexpectedGuardResultTechnicalMessage;
    case RpcRequestGuardResult.rateLimited:
      return RpcInboundConstants.rateLimitExceededForRpcRequestTechnicalMessage;
    case RpcRequestGuardResult.replayDetected:
      return RpcInboundConstants.duplicateRequestIdWithinReplayWindowTechnicalMessage;
  }
}
