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

    visit(definition.name);
    visit(definition.description);

    for (final entry in definition.policies.environment.variables.entries) {
      visit(entry.key);
      visit(entry.value);
    }

    switch (definition.config) {
      case CommandLineActionConfig(:final command):
        visit(command);
      case ExecutableActionConfig(:final arguments):
        arguments.forEach(visit);
      case ScriptActionConfig(:final arguments):
        arguments.forEach(visit);
      case JarActionConfig(:final arguments):
        arguments.forEach(visit);
      case EmailActionConfig(
        :final subjectTemplate,
        :final bodyTemplate,
        :final smtpProfileId,
        :final from,
        :final to,
        :final cc,
        :final bcc,
      ):
        visit(smtpProfileId);
        visit(from);
        visit(subjectTemplate);
        visit(bodyTemplate);
        [...to, ...cc, ...bcc].forEach(visit);
      case ComObjectActionConfig(:final arguments):
        for (final entry in arguments.entries) {
          visit(entry.key);
          final value = entry.value;
          if (value is String) {
            visit(value);
          }
        }
      case DeveloperActionConfig(:final connectionLabel):
        visit(connectionLabel);
    }

    return Set<String>.unmodifiable(names);
  }
}
