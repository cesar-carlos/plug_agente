import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/idempotency_fingerprint.dart';

void main() {
  group('idempotency fingerprint', () {
    test('should match stable digest for sql.execute params', () {
      final fp = buildIdempotencyFingerprintForEnvelope({
        'method': 'sql.execute',
        'params': {
          'sql': 'SELECT 1',
          'idempotency_key': 'k1',
        },
      });
      expect(
        fp,
        equals(
          buildIdempotencyFingerprintForEnvelope({
            'method': 'sql.execute',
            'params': {
              'idempotency_key': 'k1',
              'sql': 'SELECT 1',
            },
          }),
        ),
      );
    });

    test(
      'buildIdempotencyFingerprintForEnvelope matches buffer sha256 of JsonUtf8',
      () {
        final envelope = <String, dynamic>{
          'method': 'sql.execute',
          'params': <String, dynamic>{
            'sql': 'SELECT 1',
            'n': 3.25,
            'flag': true,
          },
        };
        final canonical = canonicalizeJsonValueForIdempotency(envelope);
        final raw = JsonUtf8Encoder().convert(canonical);
        final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
        final expected = sha256.convert(bytes).toString();
        expect(
          buildIdempotencyFingerprintForEnvelope(envelope),
          equals(expected),
        );
      },
    );

    test(
      'resolveIdempotencyFingerprint matches sync for small payload',
      () async {
        final params = <String, dynamic>{'sql': 'SELECT 1'};
        final a = buildIdempotencyFingerprintForEnvelope({
          'method': 'sql.execute',
          'params': params,
        });
        final b = await resolveIdempotencyFingerprint('sql.execute', params);
        expect(b, equals(a));
      },
    );
  });
}
