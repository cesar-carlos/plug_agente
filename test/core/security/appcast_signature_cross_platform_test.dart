import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/security/appcast_signature_verifier.dart';

void main() {
  group('Cross-platform Ed25519 verification (Python ↔ Dart)', () {
    // These vectors are produced by tool/appcast_signing.py against the same
    // canonical payload format. They lock down byte-for-byte compatibility
    // between the publishing pipeline (Python) and the verifier (Dart).
    // Regenerate with:
    //   python -c "from tool.appcast_signing import *; ..."
    // If this test fails, the canonical format diverged between languages.
    test('verifies a signature produced by tool/appcast_signing.py', () async {
      const publicKey = 'AgioCsHZr/MmqPmckUOzs5IKWwjkCRaEFgQGS3wwRNA=';
      const signature = 'ovp0ynr7pl366Yfd5IrHwg9YtUraKdQDFyLtYr39yR6QXuaUOWq0KOicUxiG9fE4SZJHLSRH4sxdTf0pe8CCCQ==';
      final payload = buildAppcastEnclosureSignable(
        version: '1.6.9+1',
        os: 'windows',
        sha256: 'aabb',
        channel: 'stable',
        rolloutPercentage: 100,
        assetUrl: 'https://example.com/x.exe',
        assetSize: 42,
      );

      final verifier = Ed25519AppcastSignatureVerifier();
      final status = await verifier.verifyEnclosure(
        canonicalPayload: payload,
        base64Signature: signature,
        base64PublicKey: publicKey,
      );
      expect(status, AppcastSignatureVerificationStatus.valid);
    });
  });
}
