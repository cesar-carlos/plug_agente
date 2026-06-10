import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_developer_editor_section.dart';

void main() {
  group('AgentActionDeveloperEditorSectionState.isReloadableData7ConfigPath', () {
    test('returns true for paths ending with Data7.Config', () {
      expect(
        AgentActionDeveloperEditorSectionState.isReloadableData7ConfigPath(r'C:\Data7\bin\Data7.Config'),
        isTrue,
      );
    });

    test('returns false for empty or incomplete paths', () {
      expect(AgentActionDeveloperEditorSectionState.isReloadableData7ConfigPath(''), isFalse);
      expect(AgentActionDeveloperEditorSectionState.isReloadableData7ConfigPath(r'C:\Data7\bin'), isFalse);
      expect(
        AgentActionDeveloperEditorSectionState.isReloadableData7ConfigPath(r'C:\Data7\bin\other.xml'),
        isFalse,
      );
    });
  });
}
