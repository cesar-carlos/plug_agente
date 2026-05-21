import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';

void main() {
  group('RpcClientTokenConstants', () {
    test('reason strings should be non-empty and distinct', () {
      final reasons = <String>[
        RpcClientTokenConstants.missingClientTokenReason,
        RpcClientTokenConstants.clientTokenAuthorizationDisabledRpcReason,
        RpcClientTokenConstants.clientTokenIntrospectionDisabledRpcReason,
        RpcClientTokenConstants.clientTokenGetPolicyRateLimitedReason,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
