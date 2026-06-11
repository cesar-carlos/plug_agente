import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/services/health/agent_actions_health_section_builder.dart';
import 'package:plug_agente/application/services/health/health_metric_helpers.dart';
import 'package:plug_agente/application/services/health/health_status_deriver.dart';
import 'package:plug_agente/application/services/health/pool_health_section_builder.dart';
import 'package:plug_agente/application/services/health/secure_storage_health_section_builder.dart';
import 'package:plug_agente/application/services/health/sql_queue_health_section_builder.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';

class _MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class _MockOdbcCredentialSecretStore extends Mock implements IOdbcCredentialSecretStore {}

class _MockHubAuthSecretStore extends Mock implements IHubAuthSecretStore {}

class _MockTokenSecretStore extends Mock implements ITokenSecretStore {}

void main() {
  group('healthMetricInt', () {
    test('returns int and num values as int', () {
      expect(healthMetricInt({'count': 3}, 'count'), 3);
      expect(healthMetricInt({'count': 3.7}, 'count'), 3);
      expect(healthMetricInt({}, 'missing'), 0);
    });
  });

  group('deriveHealthOverallStatus', () {
    test('returns degraded when native circuit is open', () {
      expect(
        deriveHealthOverallStatus(
          poolDiagnostics: const {'native_circuit_open': true},
          queuedGateway: null,
          secureStorage: null,
        ),
        'degraded',
      );
    });

    test('returns healthy when no degradation signals exist', () {
      expect(
        deriveHealthOverallStatus(
          poolDiagnostics: const {},
          queuedGateway: null,
          secureStorage: const {'degraded': false},
        ),
        'healthy',
      );
    });
  });

  group('PoolHealthSectionBuilder', () {
    test('builds pool section with fallback totals', () {
      const builder = PoolHealthSectionBuilder();
      final section = builder.build(
        metrics: const {
          'direct_connection_fallback': 2,
          'odbc_native_pool_fallback': 1,
        },
        poolDiagnostics: const {'strategy': 'lease'},
        poolActiveCount: 4,
        driverType: 'sqlServer',
      );

      expect(section['active_count'], 4);
      expect(section['driver_type'], 'sqlServer');
      expect(section['fallbacks_total'], 3);
    });
  });

  group('SqlQueueHealthSectionBuilder', () {
    test('returns disabled when gateway is null', () {
      const builder = SqlQueueHealthSectionBuilder();
      expect(builder.build(queuedGateway: null, metrics: const {}), {'enabled': false});
    });
  });

  group('SecureStorageHealthSectionBuilder', () {
    test('returns null when no stores are wired', () {
      expect(const SecureStorageHealthSectionBuilder().build(), isNull);
    });

    test('reports partial degradation', () {
      final odbcStore = _MockOdbcCredentialSecretStore();
      final hubAuthStore = _MockHubAuthSecretStore();
      final tokenStore = _MockTokenSecretStore();
      when(() => odbcStore.isAvailable).thenReturn(true);
      when(() => hubAuthStore.isAvailable).thenReturn(false);
      when(() => tokenStore.isAvailable).thenReturn(true);

      final section = SecureStorageHealthSectionBuilder(
        odbcCredentialSecretStore: odbcStore,
        hubAuthSecretStore: hubAuthStore,
        tokenSecretStore: tokenStore,
      ).build();

      expect(section!['degraded'], isTrue);
      expect(section['unavailable'], ['hub_auth']);
    });
  });

  group('AgentActionsHealthSectionBuilder', () {
    test('returns null when feature flags are not wired', () {
      expect(const AgentActionsHealthSectionBuilder().build(const {}), isNull);
    });

    test('returns enabled agent_actions when feature flags are wired', () {
      final builder = AgentActionsHealthSectionBuilder(
        featureFlags: FeatureFlags(InMemoryAppSettingsStore()),
      );
      final section = builder.build(const {});
      expect(section!['enabled'], isTrue);
      expect(section['supported_types'], ['commandLine']);
    });
  });
}
