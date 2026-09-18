import 'package:plug_agente/core/constants/agent_action_command_line_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

/// Resolves the sole supported context interpolation after the file has passed
/// canonical path validation. Diagnostics intentionally never contain the path.
class CommandLineContextTemplateResolver {
  const CommandLineContextTemplateResolver();

  Result<String> resolve({
    required String actionId,
    required String command,
    required AgentActionContextInjectionMode injectionMode,
    required String? validatedContextPath,
    String phase = 'execution_preflight',
  }) {
    final occurrences = AgentActionCommandLineConstants.contextPathPlaceholder.allMatches(command).length;
    final acceptsPlaceholder =
        injectionMode == AgentActionContextInjectionMode.argument ||
        injectionMode == AgentActionContextInjectionMode.file;
    if (validatedContextPath == null) {
      if (occurrences == 0) return Success(command);
      return Failure(
        _invalid(
          actionId: actionId,
          phase: phase,
          message: 'Command line context placeholder requires a context file.',
          userMessage:
              'Informe um arquivo de contexto ou remova o placeholder ${AgentActionCommandLineConstants.contextPathPlaceholder}.',
        ),
      );
    }
    if (!acceptsPlaceholder || occurrences != 1) {
      return Failure(
        _required(
          actionId: actionId,
          phase: phase,
          userMessage:
              'Para executar com arquivo de contexto, inclua exatamente um placeholder ${AgentActionCommandLineConstants.contextPathPlaceholder} no comando.',
        ),
      );
    }
    return Success(
      command.replaceFirst(
        AgentActionCommandLineConstants.contextPathPlaceholder,
        _quoteForCmd(validatedContextPath),
      ),
    );
  }

  ActionValidationFailure _required({required String actionId, required String phase, required String userMessage}) =>
      ActionValidationFailure.withContext(
        message: 'Command line context placeholder is required exactly once.',
        code: AgentActionFailureCode.commandLineContextPlaceholderRequired,
        context: {
          'action_id': actionId,
          'field': 'command',
          'phase': phase,
          'reason': AgentActionCommandLineConstants.contextPlaceholderRequiredReason,
          'user_message': userMessage,
        },
      );

  ActionValidationFailure _invalid({
    required String actionId,
    required String phase,
    required String message,
    required String userMessage,
  }) => ActionValidationFailure.withContext(
    message: message,
    code: AgentActionFailureCode.commandLineContextPlaceholderInvalid,
    context: {
      'action_id': actionId,
      'field': 'command',
      'phase': phase,
      'reason': AgentActionCommandLineConstants.contextPlaceholderInvalidReason,
      'user_message': userMessage,
    },
  );

  /// Unlike argv quoting, a cmd.exe template must always delimit a substituted
  /// filesystem path: names can legally contain shell metacharacters such as
  /// `&`, which must never become command operators.
  String _quoteForCmd(String path) => '"${path.replaceAll('"', '""')}"';
}
