import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_command_safety_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/action_config.dart';
import 'package:plug_agente/domain/actions/action_definition.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/actions/action_execution.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/i_action_command_safety_assessor.dart';
import 'package:result_dart/result_dart.dart';

/// Application-layer enforcement for dangerous command patterns on execution paths.
///
/// Remote and scheduler sources always use block policy. Local UI may use warn mode
/// when enabled, but still requires an explicit confirmation flag on the request.
class AgentActionDangerousCommandPolicyEnforcer {
  const AgentActionDangerousCommandPolicyEnforcer({
    required IActionCommandSafetyAssessor commandSafetyAssessor,
    FeatureFlags? featureFlags,
  }) : _commandSafetyAssessor = commandSafetyAssessor,
       _featureFlags = featureFlags;

  final IActionCommandSafetyAssessor _commandSafetyAssessor;
  final FeatureFlags? _featureFlags;

  Result<void> enforce({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
    String phase = AgentActionProcessConstants.executionPreflightPhase,
  }) {
    final invocationStrings = _invocationStringsFor(definition);
    if (invocationStrings.isEmpty) {
      return const Success(unit);
    }

    final enforceBlockPolicy = _requiresBlockPolicy(request.source);
    final warnModeEnabled =
        !enforceBlockPolicy && (_featureFlags?.enableAgentActionDangerousCommandWarnMode ?? false);

    for (final invocation in invocationStrings) {
      final assessment = _commandSafetyAssessor.assessForLocalRun(
        command: invocation,
        warnModeEnabled: warnModeEnabled,
      );

      if (assessment.policy == AgentActionDangerousCommandRunPolicy.allow) {
        continue;
      }

      final match = assessment.match;
      if (match == null) {
        continue;
      }

      if (assessment.isBlocked || enforceBlockPolicy) {
        return Failure(
          _blockedFailure(
            definition: definition,
            phase: phase,
            field: _fieldFor(definition.type),
            match: match,
          ),
        );
      }

      if (!request.dangerousCommandConfirmed) {
        return Failure(
          _confirmationRequiredFailure(
            definition: definition,
            phase: phase,
            field: _fieldFor(definition.type),
            match: match,
          ),
        );
      }
    }

    return const Success(unit);
  }

  bool _requiresBlockPolicy(AgentActionRequestSource source) {
    return switch (source) {
      AgentActionRequestSource.localUi => false,
      AgentActionRequestSource.remoteHub ||
      AgentActionRequestSource.scheduler ||
      AgentActionRequestSource.appLifecycle => true,
    };
  }

  List<String> _invocationStringsFor(AgentActionDefinition definition) {
    final config = definition.config;
    return switch (config) {
      CommandLineActionConfig() => <String>[config.command],
      ExecutableActionConfig() => _structuredInvocationStrings(
        path: config.executablePath.displayPath,
        arguments: config.arguments,
      ),
      ScriptActionConfig() => _structuredInvocationStrings(
        path: config.scriptPath.displayPath,
        arguments: config.arguments,
      ),
      _ => const <String>[],
    };
  }

  List<String> _structuredInvocationStrings({
    required String path,
    required List<String> arguments,
  }) {
    final strings = <String>[path];
    if (arguments.isEmpty) {
      return strings;
    }

    strings.add('$path ${arguments.join(' ')}');
    strings.addAll(arguments);
    return strings;
  }

  String _fieldFor(AgentActionType type) {
    return switch (type) {
      AgentActionType.commandLine => 'command',
      AgentActionType.executable => 'executablePath',
      AgentActionType.script => 'scriptPath',
      _ => 'command',
    };
  }

  ActionValidationFailure _blockedFailure({
    required AgentActionDefinition definition,
    required String phase,
    required String field,
    required AgentActionDangerousCommandMatch match,
  }) {
    return ActionValidationFailure.withContext(
      message: 'Action invocation contains a blocked dangerous pattern.',
      context: {
        'action_id': definition.id,
        'field': field,
        'phase': phase,
        'reason': AgentActionCommandSafetyConstants.dangerousCommandPatternReason,
        'pattern_id': match.patternId,
        'pattern_description': match.description,
        'user_message': AgentActionCommandSafetyConstants.userMessageBlockedPattern,
      },
    );
  }

  ActionValidationFailure _confirmationRequiredFailure({
    required AgentActionDefinition definition,
    required String phase,
    required String field,
    required AgentActionDangerousCommandMatch match,
  }) {
    return ActionValidationFailure.withContext(
      message: 'Dangerous command pattern requires explicit confirmation before local execution.',
      context: {
        'action_id': definition.id,
        'field': field,
        'phase': phase,
        'reason': AgentActionCommandSafetyConstants.dangerousCommandPatternReason,
        'pattern_id': match.patternId,
        'pattern_description': match.description,
        'confirmation_required': true,
        'user_message': AgentActionCommandSafetyConstants.userMessageDangerousCommandConfirmationRequired(
          patternId: match.patternId,
          patternDescription: match.description,
        ),
      },
    );
  }
}
