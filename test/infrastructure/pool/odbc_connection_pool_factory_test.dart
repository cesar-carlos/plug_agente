import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool_factory.dart';
import 'package:plug_agente/infrastructure/pool/odbc_native_connection_pool.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class _MockOdbcService extends Mock implements OdbcService {}

void main() {
  group('createOdbcConnectionPool', () {
    late _MockOdbcService service;

    setUp(() {
      service = _MockOdbcService();
    });

    test('returns OdbcNativeConnectionPool when useNativeOdbcPool is true', () {
      final settings = MockOdbcConnectionSettings(useNativeOdbcPool: true);
      final pool = createOdbcConnectionPool(
        service,
        settings,
        MetricsCollector(),
      );
      expect(pool, isA<OdbcNativeConnectionPool>());
    });

    test('returns lease OdbcConnectionPool by default', () {
      final settings = MockOdbcConnectionSettings();
      final pool = createOdbcConnectionPool(
        service,
        settings,
        MetricsCollector(),
      );
      expect(pool, isA<OdbcConnectionPool>());
    });
  });
}
