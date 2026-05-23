import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';

int rpcInboundValidationFailureCode(domain.Failure failure) {
  final code = failure.context['rpc_error_code'];
  return code is int ? code : RpcErrorCode.invalidRequest;
}

({int code, String? reason}) mapRpcInboundTransportDecodeFailure(domain.Failure failure) {
  if (failure is domain.ValidationFailure && failure.context['transport_signature_invalid'] == true) {
    return (
      code: RpcErrorCode.authenticationFailed,
      reason: RpcErrorCode.reasonInvalidSignature,
    );
  }
  final contextCode = failure.context['rpc_error_code'];
  if (contextCode is int) {
    return (code: contextCode, reason: null);
  }
  if (failure is domain.CompressionFailure) {
    final operation = failure.context['operation'];
    return (
      code: operation == 'decode' || operation == 'jsonDecode'
          ? RpcErrorCode.decodingFailed
          : RpcErrorCode.compressionFailed,
      reason: null,
    );
  }
  return (code: RpcErrorCode.invalidPayload, reason: null);
}
