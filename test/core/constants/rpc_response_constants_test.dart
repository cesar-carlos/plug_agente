import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/rpc_response_constants.dart';

void main() {
  group('RpcResponseConstants', () {
    test('outgoing contract validation message should be non-empty', () {
      expect(RpcResponseConstants.outgoingContractValidationFailedTechnicalMessage, isNotEmpty);
    });
  });
}
