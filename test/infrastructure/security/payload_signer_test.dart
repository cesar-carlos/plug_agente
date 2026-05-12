import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';
import 'package:plug_agente/infrastructure/security/payload_signing_canonicalizer.dart';

void main() {
  late PayloadSigner signer;

  setUp(() {
    signer = PayloadSigner(keys: {'key-1': 'super-secret-key-for-testing'});
  });

  group('PayloadSigner', () {
    test('sign should return a valid signature', () {
      final payload = {
        'method': 'sql.execute',
        'id': 1,
        'params': {'sql': 'SELECT 1'},
      };

      final signature = signer.sign(payload);

      check(signature.alg).equals('hmac-sha256');
      check(signature.keyId).equals('key-1');
      check(signature.value).isNotEmpty();
    });

    test('verify should return true for valid signature', () {
      final payload = {
        'method': 'sql.execute',
        'id': 1,
        'params': {'sql': 'SELECT 1'},
      };

      final signature = signer.sign(payload);
      final isValid = signer.verify(payload, signature);

      check(isValid).isTrue();
    });

    test('verify should return false for tampered payload', () {
      final payload = {
        'method': 'sql.execute',
        'id': 1,
        'params': {'sql': 'SELECT 1'},
      };

      final signature = signer.sign(payload);

      final tampered = {
        'method': 'sql.execute',
        'id': 1,
        'params': {'sql': 'DROP TABLE users'},
      };

      final isValid = signer.verify(tampered, signature);

      check(isValid).isFalse();
    });

    test('verify should return false for unknown key_id', () {
      final payload = {'method': 'sql.execute', 'id': 1};
      const signature = PayloadSignature(
        alg: 'hmac-sha256',
        value: 'fake-value',
        keyId: 'unknown-key',
      );

      check(signer.verify(payload, signature)).isFalse();
    });

    test('verify should return false for unsupported algorithm', () {
      final payload = {'method': 'sql.execute', 'id': 1};
      const signature = PayloadSignature(
        alg: 'hmac-sha512',
        value: 'some-value',
        keyId: 'key-1',
      );

      check(signer.verify(payload, signature)).isFalse();
    });

    test('sign only includes signable fields', () {
      final payload1 = {
        'method': 'sql.execute',
        'id': 1,
        'params': {'sql': 'SELECT 1'},
        'extra_field': 'ignored',
      };
      final payload2 = {
        'method': 'sql.execute',
        'id': 1,
        'params': {'sql': 'SELECT 1'},
      };

      final sig1 = signer.sign(payload1);
      final sig2 = signer.sign(payload2);

      check(sig1.value).equals(sig2.value);
    });

    test('different methods produce different signatures', () {
      final p1 = {'method': 'sql.execute', 'id': 1};
      final p2 = {'method': 'sql.executeBatch', 'id': 1};

      check(signer.sign(p1).value).not((s) => s.equals(signer.sign(p2).value));
    });

    test('uses active key for signing and verifies previous keys for rotation', () {
      final rotatingSigner = PayloadSigner(
        activeKeyId: 'key-2',
        keys: {
          'key-1': 'previous-secret',
          'key-2': 'current-secret',
        },
      );
      final previousSigner = PayloadSigner(keys: {'key-1': 'previous-secret'});
      final payload = {'method': 'sql.execute', 'id': 1};

      final previousSignature = previousSigner.sign(payload);
      final activeSignature = rotatingSigner.sign(payload);

      check(activeSignature.keyId).equals('key-2');
      check(rotatingSigner.verify(payload, previousSignature)).isTrue();
      check(rotatingSigner.verify(payload, activeSignature)).isTrue();
    });

    test('signFrame should verify transport metadata and binary payload', () {
      const frame = PayloadFrame(
        schemaVersion: '1.0',
        enc: 'json',
        cmp: 'gzip',
        contentType: 'application/json',
        originalSize: 128,
        compressedSize: 64,
        payload: [1, 2, 3, 4],
        traceId: 'trace-1',
        requestId: 'req-1',
      );

      final signature = signer.signFrame(frame);

      check(signer.verifyFrame(frame, signature)).isTrue();
      check(
        signer.verifyFrame(
          frame.copyWith(compressedSize: 65),
          signature,
        ),
      ).isFalse();
    });

    test('matches shared HMAC test vectors', () {
      final fixture =
          jsonDecode(
                File('test/fixtures/payload_signing_test_vectors.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final vectorSigner = PayloadSigner(
        activeKeyId: fixture['key_id'] as String,
        keys: {fixture['key_id'] as String: fixture['secret'] as String},
      );

      final logical = fixture['logical_payload'] as Map<String, dynamic>;
      final logicalPayload = Map<String, dynamic>.from(logical['payload'] as Map<String, dynamic>);
      check(
        PayloadSigningCanonicalizer.canonicalLogicalPayloadString(logicalPayload),
      ).equals(logical['canonical_input'] as String);
      check(vectorSigner.sign(logicalPayload).value).equals(logical['signature'] as String);

      final frameVector = fixture['transport_frame'] as Map<String, dynamic>;
      final frame = PayloadFrame.fromJson(
        Map<String, dynamic>.from(frameVector['frame'] as Map<String, dynamic>),
      );
      check(PayloadSigningCanonicalizer.canonicalFrameString(frame)).equals(frameVector['canonical_input'] as String);
      check(vectorSigner.signFrame(frame).value).equals(frameVector['signature'] as String);
    });
  });

  group('PayloadSignature', () {
    test('toJson and fromJson roundtrip', () {
      const original = PayloadSignature(
        alg: 'hmac-sha256',
        value: 'abc123',
        keyId: 'key-1',
      );

      final json = original.toJson();
      final restored = PayloadSignature.fromJson(json);

      check(restored.alg).equals(original.alg);
      check(restored.value).equals(original.value);
      check(restored.keyId).equals(original.keyId);
    });
  });
}
