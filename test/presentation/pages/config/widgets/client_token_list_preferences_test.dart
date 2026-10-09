import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token/client_token_section_controller.dart';
import 'package:plug_agente/presentation/pages/config/widgets/client_token_list_preferences.dart';

void main() {
  group('ClientTokenListPreferences', () {
    test('should return null when no store is available', () {
      final prefs = ClientTokenListPreferences(_noStore);

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
        pageSize: 100,
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

    test('persists every preference in one batch and preserves page size', () async {
      final store = _RecordingSettingsStore();
      final prefs = ClientTokenListPreferences(() => store);
      await prefs.save((
        clientFilter: 'acme',
        statusFilter: ClientTokenStatusFilter.active,
        sortOption: ClientTokenSortOption.oldest,
        autoRefreshAfterCreate: true,
        pageSize: 25,
      ));
      expect(store.batches, 1);
      expect(store.keys, hasLength(5));
      expect(prefs.restore()!.pageSize, 25);
    });

    test('failed batch reports typed warning without changing controller selection', () async {
      final store = _RecordingSettingsStore()..fail = true;
      final prefs = ClientTokenListPreferences(() => store);
      final result = await prefs.save((
        clientFilter: 'acme',
        statusFilter: ClientTokenStatusFilter.active,
        sortOption: ClientTokenSortOption.oldest,
        autoRefreshAfterCreate: true,
        pageSize: 100,
      ));
      expect(result.exceptionOrNull(), isA<ConfigurationFailure>());
      final controller = ClientTokenSectionController(settingsStoreLookup: () => store, onSectionChanged: () {});
      addTearDown(controller.dispose);
      controller.listClientFilterController.text = 'current';
      await controller.saveListPreferences();
      expect(controller.hasPreferenceWarning, isTrue);
      expect(controller.buildListQuery().clientIdContains, 'current');
    });

    testWidgets('clear and dispose cancel pending debounce callbacks', (tester) async {
      var calls = 0;
      final controller = ClientTokenSectionController(settingsStoreLookup: _noStore, onSectionChanged: () {});
      controller.handleClientFilterChanged(() => calls++);
      controller.clearTokenFilters();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 0);
      controller.handleClientFilterChanged(() => calls++);
      controller.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 0);
    });

    test('restoring all fields notifies the section exactly once', () {
      var calls = 0;
      final controller = ClientTokenSectionController(settingsStoreLookup: _noStore, onSectionChanged: () => calls++);
      addTearDown(controller.dispose);
      controller.applyRestoredListPreferences((
        clientFilter: 'stored',
        statusFilter: ClientTokenStatusFilter.revoked,
        sortOption: ClientTokenSortOption.clientDesc,
        autoRefreshAfterCreate: false,
        pageSize: 100,
      ));
      expect(calls, 1);
      expect(controller.buildListQuery().page, 1);
      expect(controller.buildListQuery().pageSize, 100);
    });

    test('save should be a no-op when no store is available', () async {
      final prefs = ClientTokenListPreferences(_noStore);

      await expectLater(
        prefs.save((
          clientFilter: 'x',
          statusFilter: ClientTokenStatusFilter.active,
          sortOption: ClientTokenSortOption.oldest,
          autoRefreshAfterCreate: true,
          pageSize: 50,
        )),
        completes,
      );
    });
  });
}

IAppSettingsStore? _noStore() => null;

class _RecordingSettingsStore extends InMemoryAppSettingsStore {
  int batches = 0;
  Set<String> keys = {};
  bool fail = false;
  @override
  Future<void> setValues(Map<String, Object> values) async {
    batches++;
    keys = values.keys.toSet();
    if (fail) throw Exception('injected settings failure');
    await super.setValues(values);
  }
}
