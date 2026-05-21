import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_developer_data7_constants.dart';

void main() {
  group('AgentActionDeveloperData7Constants', () {
    test('developer data7 context reason strings should be non-empty and distinct', () {
      final reasons = <String>[
        AgentActionDeveloperData7Constants.developerData7ConfigReadFailedReason,
        AgentActionDeveloperData7Constants.developerData7ConfigInvalidReason,
        AgentActionDeveloperData7Constants.developerData7ConnectionDuplicatedReason,
        AgentActionDeveloperData7Constants.developerData7ConnectionMissingReason,
        AgentActionDeveloperData7Constants.developerData7ConfigNotFoundReason,
        AgentActionDeveloperData7Constants.developerData7ConfigFileNameInvalidReason,
        AgentActionDeveloperData7Constants.developerData7ConfigInvalidPathReason,
        AgentActionDeveloperData7Constants.developerData7ConfigExtensionNotAllowedReason,
        AgentActionDeveloperData7Constants.developerData7ConfigNotAllowedReason,
        AgentActionDeveloperData7Constants.developerExecutorInvalidPathReason,
        AgentActionDeveloperData7Constants.developerExecutorNotFoundReason,
        AgentActionDeveloperData7Constants.developerExecutorExtensionNotAllowedReason,
        AgentActionDeveloperData7Constants.developerExecutorNotAllowedReason,
        AgentActionDeveloperData7Constants.developerExecutorFileNameInvalidReason,
        AgentActionDeveloperData7Constants.developerProjectInvalidPathReason,
        AgentActionDeveloperData7Constants.developerProjectNotFoundReason,
        AgentActionDeveloperData7Constants.developerProjectExtensionNotAllowedReason,
        AgentActionDeveloperData7Constants.developerProjectNotAllowedReason,
        AgentActionDeveloperData7Constants.developerData7ConnectionNotFoundReason,
        AgentActionDeveloperData7Constants.developerEngineNotSupportedReason,
        AgentActionDeveloperData7Constants.developerData7ConnectionIdInvalidReason,
        AgentActionDeveloperData7Constants.developerData7ConnectionChangedAfterSaveReason,
        AgentActionDeveloperData7Constants.developerData7ContextNotSupportedReason,
        AgentActionDeveloperData7Constants.developerData7RuntimeParametersNotSupportedReason,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
