import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/actions/action_path_reference.dart';

sealed class AgentActionConfig {
  const AgentActionConfig();

  AgentActionType get type;
}

class CommandLineActionConfig extends AgentActionConfig {
  const CommandLineActionConfig({
    required this.command,
    this.workingDirectory,
  });

  final String command;
  final AgentActionPathReference? workingDirectory;

  @override
  AgentActionType get type => AgentActionType.commandLine;
}

class ExecutableActionConfig extends AgentActionConfig {
  const ExecutableActionConfig({
    required this.executablePath,
    this.arguments = const [],
    this.workingDirectory,
  });

  final AgentActionPathReference executablePath;
  final List<String> arguments;
  final AgentActionPathReference? workingDirectory;

  @override
  AgentActionType get type => AgentActionType.executable;
}

class ScriptActionConfig extends AgentActionConfig {
  const ScriptActionConfig({
    required this.scriptPath,
    this.interpreterPath,
    this.arguments = const [],
    this.workingDirectory,
  });

  final AgentActionPathReference scriptPath;
  final AgentActionPathReference? interpreterPath;
  final List<String> arguments;
  final AgentActionPathReference? workingDirectory;

  @override
  AgentActionType get type => AgentActionType.script;
}

class JarActionConfig extends AgentActionConfig {
  const JarActionConfig({
    required this.jarPath,
    this.javaExecutablePath,
    this.arguments = const [],
    this.workingDirectory,
  });

  final AgentActionPathReference jarPath;
  final AgentActionPathReference? javaExecutablePath;
  final List<String> arguments;
  final AgentActionPathReference? workingDirectory;

  @override
  AgentActionType get type => AgentActionType.jar;
}

class EmailActionConfig extends AgentActionConfig {
  const EmailActionConfig({
    required this.smtpProfileId,
    required this.from,
    required this.to,
    required this.subjectTemplate,
    required this.bodyTemplate,
    this.cc = const [],
    this.bcc = const [],
    this.attachmentPaths = const [],
  });

  final String smtpProfileId;
  final String from;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subjectTemplate;
  final String bodyTemplate;
  final List<AgentActionPathReference> attachmentPaths;

  @override
  AgentActionType get type => AgentActionType.email;
}

class ComObjectActionConfig extends AgentActionConfig {
  const ComObjectActionConfig({
    required this.progId,
    required this.memberName,
    this.arguments = const {},
  });

  final String progId;
  final String memberName;
  final Map<String, Object?> arguments;

  @override
  AgentActionType get type => AgentActionType.comObject;
}

class DeveloperActionConfig extends AgentActionConfig {
  DeveloperActionConfig.data7Executor({
    required this.executorPath,
    required this.projectPath,
    required this.data7ConfigPath,
    required this.connectionId,
    required this.connectionLabel,
    this.connectionSnapshotHash,
  }) : engine = AgentActionDeveloperEngine.data7Executor;

  final AgentActionDeveloperEngine engine;
  final AgentActionPathReference executorPath;
  final AgentActionPathReference projectPath;
  final AgentActionPathReference data7ConfigPath;
  final String connectionId;
  final String connectionLabel;
  final String? connectionSnapshotHash;

  @override
  AgentActionType get type => AgentActionType.developer;
}
