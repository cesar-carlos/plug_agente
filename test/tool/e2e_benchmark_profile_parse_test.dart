import 'package:flutter_test/flutter_test.dart';

import '../../tool/e2e_benchmark_profile_parse.dart';

void main() {
  group('resolveOdbcE2eBenchmarkProfiles', () {
    test('returns explicit single profile when pool env is set', () {
      final resolved = resolveOdbcE2eBenchmarkProfiles(
        matrixRaw: null,
        poolModeRaw: 'native',
        poolSizeRaw: '6',
        concurrencyRaw: '3',
        defaultPoolSize: 4,
        defaultConcurrency: 1,
      );

      expect(resolved.source, OdbcE2eBenchmarkProfileSource.single);
      expect(resolved.profiles, hasLength(1));
      expect(resolved.profiles.single.key, 'native_p6_c3');
    });

    test('parses custom matrix entries', () {
      final resolved = resolveOdbcE2eBenchmarkProfiles(
        matrixRaw: 'lease:p2:c4; lease:pool=4:concurrency=8; native:2:2',
        poolModeRaw: null,
        poolSizeRaw: null,
        concurrencyRaw: null,
        defaultPoolSize: 4,
        defaultConcurrency: 1,
      );

      expect(resolved.source, OdbcE2eBenchmarkProfileSource.customMatrix);
      expect(
        resolved.profiles.map((profile) => profile.key),
        <String>[
          'lease_p2_c4',
          'lease_p4_c8',
          'native_p2_c2',
        ],
      );
    });

    test('falls back to default matrix when nothing is configured', () {
      final resolved = resolveOdbcE2eBenchmarkProfiles(
        matrixRaw: null,
        poolModeRaw: null,
        poolSizeRaw: null,
        concurrencyRaw: null,
        defaultPoolSize: 4,
        defaultConcurrency: 1,
      );

      expect(resolved.source, OdbcE2eBenchmarkProfileSource.defaultMatrix);
      expect(
        resolved.profiles.map((profile) => profile.key),
        <String>[
          'lease_p2_c4',
          'lease_p4_c8',
        ],
      );
    });

    test(
      'raises native pool size to concurrency for async worker timeout safety',
      () {
        final resolved = resolveOdbcE2eBenchmarkProfiles(
          matrixRaw: 'native:4:8',
          poolModeRaw: null,
          poolSizeRaw: null,
          concurrencyRaw: null,
          defaultPoolSize: 4,
          defaultConcurrency: 1,
        );

        expect(resolved.source, OdbcE2eBenchmarkProfileSource.customMatrix);
        expect(resolved.profiles.single.key, 'native_p8_c8');
      },
    );

    test('single native profile is normalized when pool smaller than concurrency', () {
      final resolved = resolveOdbcE2eBenchmarkProfiles(
        matrixRaw: null,
        poolModeRaw: 'native',
        poolSizeRaw: '4',
        concurrencyRaw: '8',
        defaultPoolSize: 4,
        defaultConcurrency: 1,
      );

      expect(resolved.source, OdbcE2eBenchmarkProfileSource.single);
      expect(resolved.profiles.single.key, 'native_p8_c8');
    });
  });
}
