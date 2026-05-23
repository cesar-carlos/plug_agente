/// Stable `failure.context['reason']` and dangerous command patterns for command-line actions.
abstract final class AgentActionCommandSafetyConstants {
  static const String dangerousCommandPatternReason = 'dangerous_command_pattern';

  static const String userMessageBlockedPattern =
      'O comando contem um padrao de alto risco e foi bloqueado por seguranca. Revise o comando ou solicite aprovacao operacional.';

  /// Default enforcement for MVP security hardening.
  static const AgentActionCommandSafetyMode defaultMode = AgentActionCommandSafetyMode.block;
}

enum AgentActionCommandSafetyMode {
  block,
  warn,
}

class AgentActionDangerousCommandPattern {
  const AgentActionDangerousCommandPattern({
    required this.id,
    required this.pattern,
    required this.description,
  });

  final String id;
  final String pattern;
  final String description;
}

abstract final class AgentActionDangerousCommandPatterns {
  static const List<AgentActionDangerousCommandPattern> blocked = <AgentActionDangerousCommandPattern>[
    AgentActionDangerousCommandPattern(
      id: 'format',
      pattern: r'\bformat\b',
      description: 'disk format',
    ),
    AgentActionDangerousCommandPattern(
      id: 'diskpart',
      pattern: r'\bdiskpart\b',
      description: 'disk partition tool',
    ),
    AgentActionDangerousCommandPattern(
      id: 'reg_delete',
      pattern: r'\breg(\.exe)?\s+delete\b',
      description: 'registry delete',
    ),
    AgentActionDangerousCommandPattern(
      id: 'powershell_encoded',
      pattern: r'\bpowershell(\.exe)?\b(?:\s+\S+)*\s+(-enc\b|-e\b|-encodedcommand\b)',
      description: 'powershell encoded command',
    ),
    AgentActionDangerousCommandPattern(
      id: 'pipe_invoke_expression',
      pattern: r'\|\s*(iex\b|invoke-expression\b)',
      description: 'pipe to invoke-expression',
    ),
    AgentActionDangerousCommandPattern(
      id: 'curl_pipe_shell',
      pattern: r'\b(curl|wget)\b[^\r\n|]*\|\s*(cmd|powershell|iex|invoke-expression)\b',
      description: 'download pipe to shell',
    ),
    AgentActionDangerousCommandPattern(
      id: 'del_recursive_force',
      pattern: r'\bdel(\.exe)?\s+(\/|\-)(f|s)\b',
      description: 'forced recursive delete',
    ),
    AgentActionDangerousCommandPattern(
      id: 'rmdir_recursive',
      pattern: r'\b(rmdir|rd)(\.exe)?\s+(\/|\-)s\b',
      description: 'recursive directory removal',
    ),
    AgentActionDangerousCommandPattern(
      id: 'shutdown',
      pattern: r'\bshutdown(\.exe)?\b',
      description: 'system shutdown',
    ),
    AgentActionDangerousCommandPattern(
      id: 'net_user',
      pattern: r'\bnet(\.exe)?\s+user\b',
      description: 'local account management',
    ),
    AgentActionDangerousCommandPattern(
      id: 'net_localgroup',
      pattern: r'\bnet(\.exe)?\s+localgroup\b',
      description: 'local group management',
    ),
    AgentActionDangerousCommandPattern(
      id: 'bcdedit',
      pattern: r'\bbcdedit(\.exe)?\b',
      description: 'boot configuration edit',
    ),
    AgentActionDangerousCommandPattern(
      id: 'vssadmin_delete',
      pattern: r'\bvssadmin(\.exe)?\b[^\r\n]*\bdelete\b',
      description: 'volume shadow copy delete',
    ),
    AgentActionDangerousCommandPattern(
      id: 'takeown',
      pattern: r'\btakeown(\.exe)?\b',
      description: 'take ownership',
    ),
    AgentActionDangerousCommandPattern(
      id: 'cipher_wipe',
      pattern: r'\bcipher(\.exe)?\b[^\r\n]*\b\/w\b',
      description: 'cipher directory wipe',
    ),
  ];
}
