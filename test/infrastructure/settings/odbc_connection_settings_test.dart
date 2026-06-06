import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/infrastructure/settings/odbc_connection_settings.dart';

void main() {
  group('OdbcConnectionSettings', () {
    test('migrates legacy factory default pool size 4 to current default on load', () async {
      final store = InMemoryAppSettingsStore({'odbc_pool_size': 4});
      final settings = OdbcConnectionSettings(store);

      await settings.load();

      expect(settings.poolSize, ConnectionConstants.defaultPoolSize);
      expect(store.getInt('odbc_pool_size'), ConnectionConstants.defaultPoolSize);
      expect(store.getBool('odbc_pool_size_user_configured'), isNull);
    });

    test('keeps pool size 4 when user explicitly configured it', () async {
      final store = InMemoryAppSettingsStore({
        'odbc_pool_size': 4,
        'odbc_pool_size_user_configured': true,
      });
      final settings = OdbcConnectionSettings(store);

      await settings.load();

      expect(settings.poolSize, 4);
      expect(store.getInt('odbc_pool_size'), 4);
    });

    test('does not migrate non-legacy persisted pool sizes', () async {
      final store = InMemoryAppSettingsStore({'odbc_pool_size': 7});
      final settings = OdbcConnectionSettings(store);

      await settings.load();

      expect(settings.poolSize, 7);
      expect(store.getInt('odbc_pool_size'), 7);
    });

    test('uses current default when pool size was never persisted', () async {
      final settings = OdbcConnectionSettings(InMemoryAppSettingsStore());

      await settings.load();

      expect(settings.poolSize, ConnectionConstants.defaultPoolSize);
    });

    test('setPoolSize marks pool size as user configured', () async {
      final store = InMemoryAppSettingsStore();
      final settings = OdbcConnectionSettings(store);

      await settings.setPoolSize(OdbcConnectionSettings.legacyFactoryDefaultPoolSize);
      await settings.load();

      expect(settings.poolSize, OdbcConnectionSettings.legacyFactoryDefaultPoolSize);
      expect(store.getBool('odbc_pool_size_user_configured'), isTrue);
    });
  });
}
