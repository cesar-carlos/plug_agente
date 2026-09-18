import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_actions_ui_preferences.dart';

void main() {
  group('AgentActionsUiPreferences scheduled writes', () {
    test('should persist only the latest scheduled search value', () async {
      final store = InMemoryAppSettingsStore();
      final preferences = AgentActionsUiPreferences(() => store);

      preferences.schedulePersistString(
        AgentActionsUiPreferenceKeys.definitionSearch,
        'first',
        delay: const Duration(milliseconds: 1),
      );
      preferences.schedulePersistString(
        AgentActionsUiPreferenceKeys.definitionSearch,
        'latest',
        delay: const Duration(milliseconds: 1),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(store.getString(AgentActionsUiPreferenceKeys.definitionSearch), 'latest');
    });

    test('should not restore a pending search after filters are cleared', () async {
      final store = InMemoryAppSettingsStore();
      final preferences = AgentActionsUiPreferences(() => store);

      preferences.schedulePersistString(
        AgentActionsUiPreferenceKeys.historySearch,
        'pending',
        delay: const Duration(milliseconds: 1),
      );
      preferences.cancelScheduledPersistString(AgentActionsUiPreferenceKeys.historySearch);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(store.containsKey(AgentActionsUiPreferenceKeys.historySearch), isFalse);
    });

    test('should flush the latest pending search when the page is disposed', () async {
      final store = InMemoryAppSettingsStore();
      final preferences = AgentActionsUiPreferences(() => store);

      preferences.schedulePersistString(
        AgentActionsUiPreferenceKeys.historySearch,
        'recent failure',
        delay: const Duration(days: 1),
      );
      preferences.flushScheduledStringWrites();
      await Future<void>.delayed(Duration.zero);

      expect(store.getString(AgentActionsUiPreferenceKeys.historySearch), 'recent failure');
    });
  });
}
