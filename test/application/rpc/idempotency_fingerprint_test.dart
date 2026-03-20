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
