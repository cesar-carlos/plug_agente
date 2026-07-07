@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/infrastructure/native/columnar_decompress_ffi.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/config/odbc_usage_profile_config.dart';

/// FFI-safe runtime probe for odbc_fast (use instead of importing odbc_fast in `dart run` tools).
void main() {
  const requireColumnarCompressed = bool.fromEnvironment('REQUIRE_COLUMNAR_COMPRESSED');

  test('odbc_fast runtime exports are available', () async {
    final usageProfile = resolveOdbcUsageProfile();
    final locator = ServiceLocator()
      ..initialize(
        profile: usageProfile,
        useAsync: true,
        asyncWorkerCount: 1,
        asyncMaxPendingRequests: 4,
        asyncBackpressureMode: AsyncBackpressureMode.failFast,
      );
    try {
      final service = locator.service;
      final initResult = await service.initialize();
      expect(initResult.isSuccess(), isTrue, reason: initResult.exceptionOrNull()?.toString());

      if (requireColumnarCompressed) {
        expect(
          locator.nativeConnection.supportsResultEncodingOptions,
          isTrue,
          reason: 'Required columnar/compressed runtime exports are not available.',
        );
        expect(
          isColumnarNativeDecompressAvailable,
          isTrue,
          reason: 'Native columnar decompress symbols are not available.',
        );
      }
    } finally {
      locator.shutdown();
    }
  });
}
