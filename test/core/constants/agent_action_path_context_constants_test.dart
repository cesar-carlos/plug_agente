import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';

void main() {
  group('AgentActionPathContextConstants', () {
    test('path context reason strings should be non-empty and distinct', () {
      final reasons = <String>[
        AgentActionPathContextConstants.invalidPathReason,
        AgentActionPathContextConstants.directoryNotFoundReason,
        AgentActionPathContextConstants.workingDirectoryNotAllowedReason,
        AgentActionPathContextConstants.contextExtensionNotAllowedReason,
        AgentActionPathContextConstants.contextFileNotFoundReason,
        AgentActionPathContextConstants.contextFileNotAllowedReason,
        AgentActionPathContextConstants.contextFileTooLargeReason,
        AgentActionPathContextConstants.invalidContextJsonReason,
        AgentActionPathContextConstants.invalidContextJsonSchemaReason,
        AgentActionPathContextConstants.pathChangedAfterSaveReason,
        AgentActionPathContextConstants.fileNotFoundReason,
        AgentActionPathContextConstants.fileExtensionNotAllowedReason,
        AgentActionPathContextConstants.fileNotAllowedReason,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
