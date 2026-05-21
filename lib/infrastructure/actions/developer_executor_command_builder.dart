import 'package:plug_agente/core/utils/windows_command_line_quoter.dart';
import 'package:plug_agente/domain/actions/action_redactor.dart';

class DeveloperExecutorCommand {
  const DeveloperExecutorCommand({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.redactedPreview,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final String redactedPreview;
}

class DeveloperExecutorCommandBuilder {
  const DeveloperExecutorCommandBuilder({
    AgentActionRedactor redactor = const AgentActionRedactor(),
  }) : _redactor = redactor;

  final AgentActionRedactor _redactor;

  DeveloperExecutorCommand build({
    required String executorPath,
    required String projectPath,
    required String connectionId,
    required String workingDirectory,
  }) {
    final arguments = <String>[
      '-p',
      projectPath,
      '-c',
      connectionId,
    ];
    return DeveloperExecutorCommand(
      executable: executorPath,
      arguments: List<String>.unmodifiable(arguments),
      workingDirectory: workingDirectory,
      redactedPreview: _redactor.redactText(
        WindowsCommandLineQuoter.joinArguments(<String>[
          executorPath,
          '-p',
          projectPath,
          '-c',
          connectionId,
        ]),
      ),
    );
  }
}
