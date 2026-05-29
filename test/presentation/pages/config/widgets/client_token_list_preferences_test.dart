import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_list_preferences.dart';

void main() {
  group('ClientTokenListPreferences', () {
    test('should return null when no store is available', () {
      const prefs = ClientTokenListPreferences(_noStore);

      expect(prefs.restore(), isNull);
    });

    test('should return defaults when the store has no persisted values', () {
      final store = InMemoryAppSettingsStore();
      final prefs = ClientTokenListPreferences(() => store);

      final data = prefs.restore();

      expect(data, isNotNull);
      expect(data!.clientFilter, '');
      expect(data.statusFilter, ClientTokenStatusFilter.all);
      expect(data.sortOption, ClientTokenSortOption.newest);
      expect(data.autoRefreshAfterCreate, isTrue);
    });

    test('should round-trip saved preferences back through restore', () async {
      final store = InMemoryAppSettingsStore();
      final prefs = ClientTokenListPreferences(() => store);

      await prefs.save((
        clientFilter: '  acme  ',
        statusFilter: ClientTokenStatusFilter.revoked,
        sortOption: ClientTokenSortOption.clientAsc,
        autoRefreshAfterCreate: false,
      ));

      final data = prefs.restore();

      expect(data, isNotNull);
      expect(data!.clientFilter, 'acme', reason: 'client filter should be trimmed on save');
      expect(data.statusFilter, ClientTokenStatusFilter.revoked);
      expect(data.sortOption, ClientTokenSortOption.clientAsc);
      expect(data.autoRefreshAfterCreate, isFalse);
    });

    test('should fall back to defaults for unknown stored enum values', () {
      final store = InMemoryAppSettingsStore(<String, Object>{
        ClientTokenListPreferenceKeys.statusFilter: 'garbage',
        ClientTokenListPreferenceKeys.sortFilter: 'garbage',
      });
      final prefs = ClientTokenListPreferences(() => store);

      final data = prefs.restore();

      expect(data!.statusFilter, ClientTokenStatusFilter.all);
      expect(data.sortOption, ClientTokenSortOption.newest);
    });

    test('save should be a no-op when no store is available', () async {
      const prefs = ClientTokenListPreferences(_noStore);

      await expectLater(
        prefs.save((
          clientFilter: 'x',
          statusFilter: ClientTokenStatusFilter.active,
          sortOption: ClientTokenSortOption.oldest,
          autoRefreshAfterCreate: true,
        )),
        completes,
      );
    });
  });
}

IAppSettingsStore? _noStore() => null;
