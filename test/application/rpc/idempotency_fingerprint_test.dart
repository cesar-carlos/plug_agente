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

    test('optional runtime ids change fingerprint and remain stable under key order', () {
      final params = <String, dynamic>{'action_id': 'a1', 'idempotency_key': 'k1'};
      final withoutRuntime = buildIdempotencyFingerprintForEnvelope({
        'method': 'agent.action.run',
        'params': params,
      });
      final withRuntime = buildIdempotencyFingerprintForEnvelope({
        'method': 'agent.action.run',
        'params': params,
        'runtime_instance_id': 'inst-1',
        'runtime_session_id': 'sess-1',
      });
      expect(withoutRuntime, isNot(equals(withRuntime)));
      expect(
        withRuntime,
        equals(
          buildIdempotencyFingerprintForEnvelope({
            'method': 'agent.action.run',
            'params': params,
            'runtime_session_id': 'sess-1',
            'runtime_instance_id': 'inst-1',
          }),
        ),
      );
    });

    test('resolveIdempotencyFingerprint forwards runtime ids into envelope', () async {
      final params = <String, dynamic>{'action_id': 'a1', 'idempotency_key': 'k1'};
      final expected = buildIdempotencyFingerprintForEnvelope({
        'method': 'agent.action.run',
        'params': params,
        'runtime_instance_id': 'inst-x',
        'runtime_session_id': 'sess-y',
      });
      final actual = await resolveIdempotencyFingerprint(
        'agent.action.run',
        params,
        runtimeInstanceId: 'inst-x',
        runtimeSessionId: 'sess-y',
      );
      expect(actual, equals(expected));
    });
  });
}
