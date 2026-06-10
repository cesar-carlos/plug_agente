import 'package:plug_agente/domain/actions/actions.dart';

/// Finds `${secret:name}` placeholders in action definition text fields.
class AgentActionSecretPlaceholderScanner {
  const AgentActionSecretPlaceholderScanner._();

  static final RegExp placeholderPattern = RegExp(
    r'\$\{secret:([^}]+)\}',
    caseSensitive: false,
  );

  static final RegExp _placeholderPattern = placeholderPattern;

  static Set<String> collectFromText(String value) {
    if (value.trim().isEmpty) {
      return const <String>{};
    }

    final names = <String>{};
    for (final match in _placeholderPattern.allMatches(value)) {
      final name = match.group(1)?.trim();
      if (name != null && name.isNotEmpty) {
        names.add(name);
      }
    }

    return Set<String>.unmodifiable(names);
  }

  static Set<String> collectFromDefinition(AgentActionDefinition definition) {
    final names = <String>{};

    void visit(String? value) {
      if (value == null || value.isEmpty) {
        return;
      }
      names.addAll(collectFromText(value));
    }

    void visitPath(AgentActionPathReference? path) {
      if (path == null) {
        return;
      }
      visit(path.originalPath);
      final canonicalPath = path.canonicalPath;
      if (canonicalPath != null &&
          canonicalPath.isNotEmpty &&
          canonicalPath != path.originalPath) {
        visit(canonicalPath);
      }
    }

    void visitPaths(Iterable<AgentActionPathReference> paths) {
      paths.forEach(visitPath);
    }

    visit(definition.name);
    visit(definition.description);

    for (final entry in definition.policies.environment.variables.entries) {
      visit(entry.key);
      visit(entry.value);
    }

    switch (definition.config) {
      case CommandLineActionConfig(:final command, :final workingDirectory):
        visit(command);
        visitPath(workingDirectory);
      case ExecutableActionConfig(
        :final executablePath,
        :final arguments,
        :final workingDirectory,
      ):
        visitPath(executablePath);
        visitPath(workingDirectory);
        arguments.forEach(visit);
      case ScriptActionConfig(
        :final scriptPath,
        :final interpreterPath,
        :final arguments,
        :final workingDirectory,
      ):
        visitPath(scriptPath);
        visitPath(interpreterPath);
        visitPath(workingDirectory);
        arguments.forEach(visit);
      case JarActionConfig(
        :final jarPath,
        :final javaExecutablePath,
        :final arguments,
        :final workingDirectory,
      ):
        visitPath(jarPath);
        visitPath(javaExecutablePath);
        visitPath(workingDirectory);
        arguments.forEach(visit);
      case EmailActionConfig(
        :final subjectTemplate,
        :final bodyTemplate,
        :final smtpProfileId,
        :final from,
        :final to,
        :final cc,
        :final bcc,
        :final attachmentPaths,
      ):
        visit(smtpProfileId);
        visit(from);
        visit(subjectTemplate);
        visit(bodyTemplate);
        [...to, ...cc, ...bcc].forEach(visit);
        visitPaths(attachmentPaths);
      case ComObjectActionConfig(:final progId, :final memberName, :final arguments):
        visit(progId);
        visit(memberName);
        for (final entry in arguments.entries) {
          visit(entry.key);
          final value = entry.value;
          if (value is String) {
            visit(value);
          }
        }
      case DeveloperActionConfig(
        :final executorPath,
        :final projectPath,
        :final data7ConfigPath,
        :final connectionLabel,
      ):
        visitPath(executorPath);
        visitPath(projectPath);
        visitPath(data7ConfigPath);
        visit(connectionLabel);
    }

    return Set<String>.unmodifiable(names);
  }
}
