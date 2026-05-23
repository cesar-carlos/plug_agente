import 'package:plug_agente/core/constants/agent_action_command_safety_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';

class ActionCommandSafetyMatch {
  const ActionCommandSafetyMatch({
    required this.patternId,
    required this.description,
  });

  final String patternId;
  final String description;
}

class ActionCommandSafetyValidator {
  const ActionCommandSafetyValidator({
    List<AgentActionDangerousCommandPattern>? patterns,
    AgentActionCommandSafetyMode mode = AgentActionCommandSafetyConstants.defaultMode,
  }) : _patterns = patterns ?? AgentActionDangerousCommandPatterns.blocked,
       _mode = mode;

  final List<AgentActionDangerousCommandPattern> _patterns;
  final AgentActionCommandSafetyMode _mode;

  ActionCommandSafetyMatch? findMatch(String command) {
    final normalized = command.trim();
    if (normalized.isEmpty) {
      return null;
    }

    for (final pattern in _patterns) {
      if (RegExp(pattern.pattern, caseSensitive: false).hasMatch(normalized)) {
        return ActionCommandSafetyMatch(
          patternId: pattern.id,
          description: pattern.description,
        );
      }
    }

    return null;
  }

  ActionValidationFailure? validate({
    required String actionId,
    required String command,
    required String phase,
    AgentActionCommandSafetyMode? mode,
  }) {
    final match = findMatch(command);
    if (match == null) {
      return null;
    }

    final effectiveMode = mode ?? _mode;
    if (effectiveMode == AgentActionCommandSafetyMode.warn) {
      return null;
    }

    return ActionValidationFailure.withContext(
      message: 'Command line action contains a blocked dangerous pattern.',
      context: {
        'action_id': actionId,
        'field': 'command',
        'phase': phase,
        'reason': AgentActionCommandSafetyConstants.dangerousCommandPatternReason,
        'pattern_id': match.patternId,
        'pattern_description': match.description,
        'user_message': AgentActionCommandSafetyConstants.userMessageBlockedPattern,
      },
    );
  }

  String? warningMessageFor(String command) {
    final match = findMatch(command);
    if (match == null) {
      return null;
    }

    return 'O comando contem um padrao de alto risco (${match.patternId}). Revise antes de executar em producao.';
  }
}
