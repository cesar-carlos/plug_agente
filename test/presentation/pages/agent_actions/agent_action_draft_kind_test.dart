import 'package:plug_agente/core/utils/powershell_command_line.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:test/test.dart';

void main() {
  group('agentActionTypeForDraftKind', () {
    test('should map each non-PowerShell kind to its action type', () {
      expect(
        agentActionTypeForDraftKind(AgentActionDraftKind.commandLine, PowerShellDraftMode.inline),
        AgentActionType.commandLine,
      );
      expect(
        agentActionTypeForDraftKind(AgentActionDraftKind.executable, PowerShellDraftMode.inline),
        AgentActionType.executable,
      );
      expect(
        agentActionTypeForDraftKind(AgentActionDraftKind.script, PowerShellDraftMode.inline),
        AgentActionType.script,
      );
      expect(
        agentActionTypeForDraftKind(AgentActionDraftKind.jar, PowerShellDraftMode.inline),
        AgentActionType.jar,
      );
      expect(
        agentActionTypeForDraftKind(AgentActionDraftKind.email, PowerShellDraftMode.inline),
        AgentActionType.email,
      );
      expect(
        agentActionTypeForDraftKind(AgentActionDraftKind.comObject, PowerShellDraftMode.inline),
        AgentActionType.comObject,
      );
      expect(
        agentActionTypeForDraftKind(AgentActionDraftKind.developer, PowerShellDraftMode.inline),
        AgentActionType.developer,
      );
    });

    test('should map PowerShell inline mode to a command line action', () {
      expect(
        agentActionTypeForDraftKind(AgentActionDraftKind.powerShell, PowerShellDraftMode.inline),
        AgentActionType.commandLine,
      );
    });

    test('should map PowerShell script mode to a script action', () {
      expect(
        agentActionTypeForDraftKind(AgentActionDraftKind.powerShell, PowerShellDraftMode.script),
        AgentActionType.script,
      );
    });
  });

  group('powerShellExecutableName', () {
    test('should map to the matching PowerShell host executable', () {
      expect(
        powerShellExecutableName(PowerShellExecutable.windowsPowerShell),
        PowerShellCommandLine.windowsPowerShellExecutable,
      );
      expect(
        powerShellExecutableName(PowerShellExecutable.powerShell7),
        PowerShellCommandLine.powerShell7Executable,
      );
    });
  });
}
