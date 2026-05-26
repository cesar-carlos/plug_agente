import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/security/appcast_signature_verifier.dart';

void main() {
  group('buildAppcastEnclosureSignable', () {
    test('writes fields in deterministic lexicographic order', () {
      final payload = buildAppcastEnclosureSignable(
        version: '1.6.9+1',
        os: 'windows',
        sha256: 'AABBCC',
        channel: 'stable',
        rolloutPercentage: 100,
        assetUrl: 'https://example.com/PlugAgente-Setup-1.6.9.exe',
        assetSize: 21173534,
      );

      expect(payload, equals('asset_size=21173534\n'
          'asset_url=https://example.com/PlugAgente-Setup-1.6.9.exe\n'
          'channel=stable\n'
          'os=windows\n'
          'rollout_percentage=100\n'
          'sha256=aabbcc\n'
          'version=1.6.9+1\n'));
    });
  });

  group('Ed25519AppcastSignatureVerifier', () {
    test('returns missing when no signature is provided', () async {
      final verifier = Ed25519AppcastSignatureVerifier();
      final status = await verifier.verifyEnclosure(
        canonicalPayload: 'anything',
        base64Signature: null,
        base64PublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      );
      expect(status, AppcastSignatureVerificationStatus.missing);
    });

    test('returns publicKeyUnavailable when key not configured', () async {
      final verifier = Ed25519AppcastSignatureVerifier();
      final status = await verifier.verifyEnclosure(
        canonicalPayload: 'anything',
        base64Signature: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        base64PublicKey: null,
      );
      expect(status, AppcastSignatureVerificationStatus.publicKeyUnavailable);
    });

    test('returns malformed when signature is not base64', () async {
      final verifier = Ed25519AppcastSignatureVerifier();
      final status = await verifier.verifyEnclosure(
        canonicalPayload: 'anything',
        base64Signature: 'not-base64!',
        base64PublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      );
      expect(status, AppcastSignatureVerificationStatus.malformed);
    });

    test('returns malformed when public key has wrong length', () async {
      final verifier = Ed25519AppcastSignatureVerifier();
      final status = await verifier.verifyEnclosure(
        canonicalPayload: 'anything',
        base64Signature: base64Encode(List<int>.filled(64, 0)),
        base64PublicKey: base64Encode(<int>[1, 2, 3]),
      );
      expect(status, AppcastSignatureVerificationStatus.malformed);
    });

    test('round trip: sign with Ed25519, verify reports valid', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      const payload = 'asset_url=https://example.com/setup.exe\nversion=1.0.0\n';

      final signature = await algorithm.sign(utf8.encode(payload), keyPair: keyPair);

      final verifier = Ed25519AppcastSignatureVerifier(algorithm: algorithm);
      final status = await verifier.verifyEnclosure(
        canonicalPayload: payload,
        base64Signature: base64Encode(signature.bytes),
        base64PublicKey: base64Encode(publicKey.bytes),
      );
      expect(status, AppcastSignatureVerificationStatus.valid);
    });

    test('returns invalid when payload differs from the signed bytes', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      const signedPayload = 'version=1.0.0\n';

      final signature = await algorithm.sign(utf8.encode(signedPayload), keyPair: keyPair);

      final verifier = Ed25519AppcastSignatureVerifier(algorithm: algorithm);
      final status = await verifier.verifyEnclosure(
        canonicalPayload: 'version=1.0.1\n',
        base64Signature: base64Encode(signature.bytes),
        base64PublicKey: base64Encode(publicKey.bytes),
      );
      expect(status, AppcastSignatureVerificationStatus.invalid);
    });

    test('returns invalid when public key does not match the signing key', () async {
      final algorithm = Ed25519();
      final signingKeyPair = await algorithm.newKeyPair();
      final otherKeyPair = await algorithm.newKeyPair();
      final otherPublic = await otherKeyPair.extractPublicKey();
      const payload = 'version=1.0.0\n';

      final signature = await algorithm.sign(utf8.encode(payload), keyPair: signingKeyPair);

      final verifier = Ed25519AppcastSignatureVerifier(algorithm: algorithm);
      final status = await verifier.verifyEnclosure(
        canonicalPayload: payload,
        base64Signature: base64Encode(signature.bytes),
        base64PublicKey: base64Encode(otherPublic.bytes),
      );
      expect(status, AppcastSignatureVerificationStatus.invalid);
    });
  });
}
