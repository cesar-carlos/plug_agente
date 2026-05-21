import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';

void main() {
  group('AuthorizationContextConstants', () {
    test('authorization context reason strings should be non-empty and distinct', () {
      final reasons = <String>[
        AuthorizationContextConstants.tokenRevokedReason,
        AuthorizationContextConstants.tokenNotFoundReason,
        AuthorizationContextConstants.invalidTokenSignatureReason,
        AuthorizationContextConstants.invalidPolicyReason,
        AuthorizationContextConstants.unauthorizedReason,
        AuthorizationContextConstants.jwksCircuitOpenReason,
        AuthorizationContextConstants.invalidJwksConfigReason,
        AuthorizationContextConstants.tokenExpiredReason,
        AuthorizationContextConstants.tokenNotYetValidReason,
        AuthorizationContextConstants.tokenVersionConflictReason,
        AuthorizationContextConstants.authorizationDeniedReason,
        AuthorizationContextConstants.unexpectedFailureTypeReason,
        AuthorizationContextConstants.databaseRequiredReason,
        AuthorizationContextConstants.databaseMismatchReason,
        AuthorizationContextConstants.missingPermissionReason,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
