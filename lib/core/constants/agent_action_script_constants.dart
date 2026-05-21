/// Limits and allowlists for `AgentActionType.script` actions.
abstract final class AgentActionScriptConstants {
  static const Set<String> allowedScriptExtensions = <String>{
    '.ps1',
    '.bat',
    '.cmd',
    '.py',
  };

  static const Set<String> allowedInterpreterExtensions = <String>{'.exe'};

  static const Map<String, String> defaultInterpreterExecutableNames = <String, String>{
    '.ps1': 'powershell.exe',
    '.bat': 'cmd.exe',
    '.cmd': 'cmd.exe',
    '.py': 'python.exe',
  };

  static const String unsupportedScriptExtensionReason = 'unsupported_script_extension';

  static const String unsupportedInterpreterForScriptReason = 'unsupported_interpreter_for_script';

  static const String interpreterRequiredReason = 'interpreter_required';
}
