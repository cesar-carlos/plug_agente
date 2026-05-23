import 'agent_actions/agent_actions_actions_tab_test.dart' as actions_tab;
import 'agent_actions/agent_actions_settings_tab_test.dart' as settings_tab;

/// Backward-compatible entry for CI paths that still target this file.
void main() {
  settings_tab.main();
  actions_tab.main();
}
