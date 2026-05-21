/// Limits and allowlists for `AgentActionType.jar` actions.
abstract final class AgentActionJarConstants {
  static const Set<String> allowedJarExtensions = <String>{'.jar'};

  static const Set<String> allowedJavaExecutableExtensions = <String>{'.exe'};

  static const String defaultJavaExecutableName = 'java.exe';

  static const String javaRequiredReason = 'java_required';
}
