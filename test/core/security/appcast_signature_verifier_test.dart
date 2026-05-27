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

  group('Multi-key rotation', () {
    test('accepts signature when ANY of the listed keys matches', () async {
      final algorithm = Ed25519();
      final activeKeyPair = await algorithm.newKeyPair();
      final activePublic = await activeKeyPair.extractPublicKey();
      final retiredKeyPair = await algorithm.newKeyPair();
      final retiredPublic = await retiredKeyPair.extractPublicKey();
      const payload = 'asset_url=https://example.com/setup.exe\nversion=1.0.0\n';

      // Signed by the active key.
      final signature = await algorithm.sign(utf8.encode(payload), keyPair: activeKeyPair);

      final verifier = Ed25519AppcastSignatureVerifier(algorithm: algorithm);
      // Build configures both retired and active keys (CSV).
      final status = await verifier.verifyEnclosure(
        canonicalPayload: payload,
        base64Signature: base64Encode(signature.bytes),
        base64PublicKey: '${base64Encode(retiredPublic.bytes)},${base64Encode(activePublic.bytes)}',
      );
      expect(status, AppcastSignatureVerificationStatus.valid);
    });

    test('returns invalid when none of multiple keys match', () async {
      final algorithm = Ed25519();
      final signingKeyPair = await algorithm.newKeyPair();
      final other1 = await (await algorithm.newKeyPair()).extractPublicKey();
      final other2 = await (await algorithm.newKeyPair()).extractPublicKey();
      const payload = 'version=1.0.0\n';

      final signature = await algorithm.sign(utf8.encode(payload), keyPair: signingKeyPair);

      final verifier = Ed25519AppcastSignatureVerifier(algorithm: algorithm);
      final status = await verifier.verifyEnclosure(
        canonicalPayload: payload,
        base64Signature: base64Encode(signature.bytes),
        base64PublicKey: '${base64Encode(other1.bytes)},${base64Encode(other2.bytes)}',
      );
      expect(status, AppcastSignatureVerificationStatus.invalid);
    });

    test('ignores malformed entries in CSV when at least one key has valid shape', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      const payload = 'version=1.0.0\n';

      final signature = await algorithm.sign(utf8.encode(payload), keyPair: keyPair);

      final verifier = Ed25519AppcastSignatureVerifier(algorithm: algorithm);
      // CSV with one garbage entry then a valid entry; verifier must succeed.
      final status = await verifier.verifyEnclosure(
        canonicalPayload: payload,
        base64Signature: base64Encode(signature.bytes),
        base64PublicKey: 'not-base64!,${base64Encode(publicKey.bytes)}',
      );
      expect(status, AppcastSignatureVerificationStatus.valid);
    });

    test('returns malformed when every CSV entry is invalid', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();
      final signature = await algorithm.sign(utf8.encode('payload'), keyPair: keyPair);
      final verifier = Ed25519AppcastSignatureVerifier(algorithm: algorithm);

      final status = await verifier.verifyEnclosure(
        canonicalPayload: 'payload',
        base64Signature: base64Encode(signature.bytes),
        base64PublicKey: 'not-base64!,also-not-base64',
      );
      expect(status, AppcastSignatureVerificationStatus.malformed);
    });

    test('trims whitespace around CSV entries', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      const payload = 'version=1.0.0\n';

      final signature = await algorithm.sign(utf8.encode(payload), keyPair: keyPair);

      final verifier = Ed25519AppcastSignatureVerifier(algorithm: algorithm);
      final status = await verifier.verifyEnclosure(
        canonicalPayload: payload,
        base64Signature: base64Encode(signature.bytes),
        base64PublicKey: '  ${base64Encode(publicKey.bytes)}  , ',
      );
      expect(status, AppcastSignatureVerificationStatus.valid);
    });
  });

  group('parseAppcastPublicKeys', () {
    test('returns empty list for null/blank input', () {
      expect(parseAppcastPublicKeys(null), isEmpty);
      expect(parseAppcastPublicKeys(''), isEmpty);
      expect(parseAppcastPublicKeys('   '), isEmpty);
    });

    test('returns single entry for non-CSV input', () {
      expect(parseAppcastPublicKeys('abc=='), <String>['abc==']);
    });

    test('splits CSV and trims whitespace', () {
      expect(
        parseAppcastPublicKeys(' key1, key2 ,  key3 '),
        <String>['key1', 'key2', 'key3'],
      );
    });

    test('drops empty entries from CSV', () {
      expect(
        parseAppcastPublicKeys('key1,,key2,'),
        <String>['key1', 'key2'],
      );
    });
  });
}
