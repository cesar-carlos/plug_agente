import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/adaptive_odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool_factory.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class _MockOdbcService extends Mock implements OdbcService {}

class _MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

void main() {
  group('createOdbcConnectionPool', () {
    late _MockOdbcService service;
    late _MockAgentConfigRepository configRepository;

    setUp(() {
      service = _MockOdbcService();
      configRepository = _MockAgentConfigRepository();
    });

    test('ignores legacy native pool setting and returns lease OdbcConnectionPool', () {
      final settings = MockOdbcConnectionSettings(useNativeOdbcPool: true);
      final pool = createOdbcConnectionPool(
        service,
        settings,
        MetricsCollector(),
        FeatureFlags(InMemoryAppSettingsStore()),
        configRepository,
      );
      expect(pool, isA<OdbcConnectionPool>());
    });

    test('returns lease OdbcConnectionPool by default', () {
      final settings = MockOdbcConnectionSettings();
      final pool = createOdbcConnectionPool(
        service,
        settings,
        MetricsCollector(),
        FeatureFlags(InMemoryAppSettingsStore()),
        configRepository,
      );
      expect(pool, isA<OdbcConnectionPool>());
    });

    test('returns adaptive pool when experimental flag is enabled', () async {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableOdbcExperimentalDriverAdaptivePooling(true);
      final settings = MockOdbcConnectionSettings();
      final pool = createOdbcConnectionPool(
        service,
        settings,
        MetricsCollector(),
        flags,
        configRepository,
      );

      expect(pool, isA<AdaptiveOdbcConnectionPool>());
    });
  });
}
