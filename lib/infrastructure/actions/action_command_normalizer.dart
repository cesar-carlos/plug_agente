import 'dart:io';

import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_command_safety_constants.dart';
import 'package:plug_agente/core/constants/agent_action_executable_constants.dart';
import 'package:plug_agente/core/constants/agent_action_jar_constants.dart';
import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/constants/agent_action_script_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/core/utils/windows_command_line_quoter.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_command_safety_validator.dart';
import 'package:result_dart/result_dart.dart';

class AgentActionCommandInvocation {
  const AgentActionCommandInvocation({
    required this.executable,
    required this.arguments,
    required this.runInShell,
    required this.mode,
    required this.redactedPreview,
    required this.normalizedCommandLength,
  });

  final String executable;
  final List<String> arguments;
  final bool runInShell;
  final ProcessStartMode mode;
  final String redactedPreview;
  final int normalizedCommandLength;
}

class ActionCommandNormalizer {
  const ActionCommandNormalizer({
    ActionCommandSafetyValidator commandSafetyValidator = const ActionCommandSafetyValidator(),
    FeatureFlags? featureFlags,
  }) : _commandSafetyValidator = commandSafetyValidator,
       _featureFlags = featureFlags;

  final ActionCommandSafetyValidator _commandSafetyValidator;
  final FeatureFlags? _featureFlags;

  AgentActionCommandSafetyMode get _commandSafetyMode {
    if (_featureFlags?.enableAgentActionDangerousCommandWarnMode ?? false) {
      return AgentActionCommandSafetyMode.warn;
    }

    return AgentActionCommandSafetyConstants.defaultMode;
  }

  Result<AgentActionCommandInvocation> normalizeCommandLine({
    required String actionId,
    required String command,
    String phase = 'definition_validation',
  }) {
    final normalizedCommand = command.trim();
    if (normalizedCommand.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Command line action command is required.',
          context: {
            'action_id': actionId,
            'field': 'command',
            'phase': phase,
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe o comando que sera executado pela linha de comando.',
          },
        ),
      );
    }

    final safetyFailure = _commandSafetyValidator.validate(
      actionId: actionId,
      command: normalizedCommand,
      phase: phase,
      mode: _commandSafetyMode,
    );
    if (safetyFailure != null) {
      return Failure(safetyFailure);
    }

    return Success(
      AgentActionCommandInvocation(
        executable: 'cmd.exe',
        arguments: <String>['/C', normalizedCommand],
        runInShell: false,
        mode: ProcessStartMode.normal,
        redactedPreview: WindowsCommandLineQuoter.joinArguments(
          <String>['cmd.exe', '/C', '[REDACTED_COMMAND]'],
        ),
        normalizedCommandLength: normalizedCommand.length,
      ),
    );
  }

  Result<AgentActionCommandInvocation> normalizeExecutable({
    required String actionId,
    required String executableCanonicalPath,
    required List<String> arguments,
    String phase = 'definition_validation',
  }) {
    final normalizedExecutable = executableCanonicalPath.trim();
    if (normalizedExecutable.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Executable action path is required.',
          context: {
            'action_id': actionId,
            'field': 'executablePath',
            'phase': phase,
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe o executavel ou arquivo .bat que sera iniciado pela acao.',
          },
        ),
      );
    }

    final normalizedArgumentsResult = _normalizeStructuredArguments(
      actionId: actionId,
      field: 'arguments',
      arguments: arguments,
      phase: phase,
    );
    if (normalizedArgumentsResult.isError()) {
      return Failure(normalizedArgumentsResult.exceptionOrNull()!);
    }
    final normalizedArguments = normalizedArgumentsResult.getOrThrow();
    final extension = _extensionOf(normalizedExecutable);

    if (extension == '.bat' || extension == '.cmd') {
      final invocationArguments = <String>[
        AgentActionProcessConstants.cmdExecuteOnceSwitch,
        normalizedExecutable,
        ...normalizedArguments,
      ];
      return Success(
        AgentActionCommandInvocation(
          executable: AgentActionProcessConstants.windowsCmdExecutable,
          arguments: invocationArguments,
          runInShell: false,
          mode: ProcessStartMode.normal,
          redactedPreview: _buildRedactedProcessPreview(
            executable: AgentActionProcessConstants.windowsCmdExecutable,
            prefixArguments: <String>[
              AgentActionProcessConstants.cmdExecuteOnceSwitch,
              normalizedExecutable,
            ],
            redactedArguments: normalizedArguments,
          ),
          normalizedCommandLength: invocationArguments.fold<int>(
            0,
            (int total, String argument) => total + argument.length,
          ),
        ),
      );
    }

    return Success(
      AgentActionCommandInvocation(
        executable: normalizedExecutable,
        arguments: normalizedArguments,
        runInShell: false,
        mode: ProcessStartMode.normal,
        redactedPreview: _buildRedactedProcessPreview(
          executable: normalizedExecutable,
          redactedArguments: normalizedArguments,
        ),
        normalizedCommandLength: normalizedArguments.fold<int>(
          0,
          (int total, String argument) => total + argument.length,
        ),
      ),
    );
  }

  Result<AgentActionCommandInvocation> normalizeScript({
    required String actionId,
    required String scriptCanonicalPath,
    required String interpreterCanonicalPath,
    required List<String> arguments,
    String phase = 'definition_validation',
  }) {
    final normalizedScript = scriptCanonicalPath.trim();
    if (normalizedScript.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Script action path is required.',
          context: {
            'action_id': actionId,
            'field': 'scriptPath',
            'phase': phase,
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe o arquivo de script que sera executado pela acao.',
          },
        ),
      );
    }

    final normalizedInterpreter = interpreterCanonicalPath.trim();
    if (normalizedInterpreter.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Script action interpreter is required.',
          context: {
            'action_id': actionId,
            'field': 'interpreterPath',
            'phase': phase,
            'reason': AgentActionScriptConstants.interpreterRequiredReason,
            'user_message': 'Nao foi possivel resolver o interpretador para este script.',
          },
        ),
      );
    }

    final normalizedArgumentsResult = _normalizeStructuredArguments(
      actionId: actionId,
      field: 'arguments',
      arguments: arguments,
      phase: phase,
    );
    if (normalizedArgumentsResult.isError()) {
      return Failure(normalizedArgumentsResult.exceptionOrNull()!);
    }
    final normalizedArguments = normalizedArgumentsResult.getOrThrow();
    final scriptExtension = _extensionOf(normalizedScript);
    if (scriptExtension == null ||
        !AgentActionScriptConstants.allowedScriptExtensions.contains(scriptExtension)) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Script extension is not supported.',
          context: {
            'action_id': actionId,
            'field': 'scriptPath',
            'phase': phase,
            'extension': scriptExtension ?? '',
            'allowed_extensions': AgentActionScriptConstants.allowedScriptExtensions.toList(growable: false),
            'reason': AgentActionScriptConstants.unsupportedScriptExtensionReason,
            'user_message': 'Selecione um script .ps1, .bat, .cmd ou .py permitido para esta acao.',
          },
        ),
      );
    }

    final interpreterName = _fileNameOf(normalizedInterpreter).toLowerCase();
    final invocationArgumentsResult = _resolveScriptInvocationArguments(
      actionId: actionId,
      scriptExtension: scriptExtension,
      interpreterName: interpreterName,
      normalizedScript: normalizedScript,
      normalizedArguments: normalizedArguments,
      phase: phase,
    );
    if (invocationArgumentsResult.isError()) {
      return Failure(invocationArgumentsResult.exceptionOrNull()!);
    }

    final resolvedArguments = invocationArgumentsResult.getOrThrow();
    final scriptName = _fileNameOf(normalizedScript);
    final prefixArgumentCount = resolvedArguments.length - normalizedArguments.length;

    return Success(
      AgentActionCommandInvocation(
        executable: normalizedInterpreter,
        arguments: resolvedArguments,
        runInShell: false,
        mode: ProcessStartMode.normal,
        redactedPreview: _buildRedactedProcessPreview(
          executable: normalizedInterpreter,
          prefixArguments: resolvedArguments.take(prefixArgumentCount).toList(growable: false),
          redactedArguments: normalizedArguments,
          labelSuffix: ' -> $scriptName',
        ),
        normalizedCommandLength: resolvedArguments.fold<int>(
          0,
          (int total, String argument) => total + argument.length,
        ),
      ),
    );
  }

  Result<AgentActionCommandInvocation> normalizeJar({
    required String actionId,
    required String jarCanonicalPath,
    required String javaExecutablePath,
    required List<String> arguments,
    String phase = 'definition_validation',
  }) {
    final normalizedJar = jarCanonicalPath.trim();
    if (normalizedJar.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Jar action path is required.',
          context: {
            'action_id': actionId,
            'field': 'jarPath',
            'phase': phase,
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe o arquivo .jar que sera executado pela acao.',
          },
        ),
      );
    }

    final normalizedJava = javaExecutablePath.trim();
    if (normalizedJava.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Jar action Java executable is required.',
          context: {
            'action_id': actionId,
            'field': 'javaExecutablePath',
            'phase': phase,
            'reason': AgentActionJarConstants.javaRequiredReason,
            'user_message': 'Nao foi possivel resolver o Java para executar este .jar.',
          },
        ),
      );
    }

    final extension = _extensionOf(normalizedJar);
    if (extension != '.jar') {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Jar action requires a .jar file.',
          context: {
            'action_id': actionId,
            'field': 'jarPath',
            'phase': phase,
            'extension': extension ?? '',
            'allowed_extensions': AgentActionJarConstants.allowedJarExtensions.toList(growable: false),
            'reason': AgentActionPathContextConstants.fileExtensionNotAllowedReason,
            'user_message': 'Selecione um arquivo .jar valido para esta acao.',
          },
        ),
      );
    }

    final normalizedArgumentsResult = _normalizeStructuredArguments(
      actionId: actionId,
      field: 'arguments',
      arguments: arguments,
      phase: phase,
    );
    if (normalizedArgumentsResult.isError()) {
      return Failure(normalizedArgumentsResult.exceptionOrNull()!);
    }
    final normalizedArguments = normalizedArgumentsResult.getOrThrow();
    final jarName = _fileNameOf(normalizedJar);
    final invocationArguments = <String>[
      '-jar',
      normalizedJar,
      ...normalizedArguments,
    ];

    return Success(
      AgentActionCommandInvocation(
        executable: normalizedJava,
        arguments: invocationArguments,
        runInShell: false,
        mode: ProcessStartMode.normal,
        redactedPreview: _buildRedactedProcessPreview(
          executable: normalizedJava,
          prefixArguments: <String>['-jar', normalizedJar],
          redactedArguments: normalizedArguments,
          labelSuffix: ' ($jarName)',
        ),
        normalizedCommandLength: invocationArguments.fold<int>(
          0,
          (total, argument) => total + argument.length,
        ),
      ),
    );
  }

  Result<List<String>> _resolveScriptInvocationArguments({
    required String actionId,
    required String scriptExtension,
    required String interpreterName,
    required String normalizedScript,
    required List<String> normalizedArguments,
    required String phase,
  }) {
    return switch (scriptExtension) {
      '.ps1' => Success(<String>[
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        normalizedScript,
        ...normalizedArguments,
      ]),
      '.bat' || '.cmd' => _buildCmdScriptArguments(
        actionId: actionId,
        interpreterName: interpreterName,
        scriptPath: normalizedScript,
        arguments: normalizedArguments,
        phase: phase,
      ),
      '.py' => Success(<String>[
        normalizedScript,
        ...normalizedArguments,
      ]),
      _ => Failure(
        ActionValidationFailure.withContext(
          message: 'Script extension is not supported.',
          context: {
            'action_id': actionId,
            'field': 'scriptPath',
            'phase': phase,
            'extension': scriptExtension,
            'reason': AgentActionScriptConstants.unsupportedScriptExtensionReason,
            'user_message': 'Selecione um script .ps1, .bat, .cmd ou .py permitido para esta acao.',
          },
        ),
      ),
    };
  }

  Result<List<String>> _buildCmdScriptArguments({
    required String actionId,
    required String interpreterName,
    required String scriptPath,
    required List<String> arguments,
    required String phase,
  }) {
    if (interpreterName != 'cmd.exe') {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Batch scripts require cmd.exe as interpreter.',
          context: {
            'action_id': actionId,
            'field': 'interpreterPath',
            'phase': phase,
            'interpreter': interpreterName,
            'reason': AgentActionScriptConstants.unsupportedInterpreterForScriptReason,
            'user_message': 'Scripts .bat e .cmd precisam usar cmd.exe como interpretador.',
          },
        ),
      );
    }

    return Success(<String>[
      '/C',
      scriptPath,
      ...arguments,
    ]);
  }

  Result<List<String>> _normalizeStructuredArguments({
    required String actionId,
    required String field,
    required List<String> arguments,
    required String phase,
  }) {
    if (arguments.length > AgentActionExecutableConstants.maxArguments) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Executable action has too many arguments.',
          context: {
            'action_id': actionId,
            'field': field,
            'phase': phase,
            'argument_count': arguments.length,
            'max_arguments': AgentActionExecutableConstants.maxArguments,
            'reason': AgentActionExecutableConstants.tooManyArgumentsReason,
            'user_message': 'Reduza a quantidade de argumentos configurados para esta acao.',
          },
        ),
      );
    }

    final normalizedArguments = <String>[];
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index].trim();
      final invalidCharactersResult = _rejectDisallowedArgumentCharacters(
        actionId: actionId,
        field: field,
        argument: argument,
        argumentIndex: index,
        phase: phase,
      );
      if (invalidCharactersResult != null) {
        return Failure(invalidCharactersResult);
      }
      if (argument.isEmpty) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Executable action arguments cannot contain blank values.',
            context: {
              'action_id': actionId,
            'field': field,
            'phase': phase,
            'argument_index': index,
            'reason': AgentActionExecutableConstants.invalidArgumentsReason,
              'user_message': 'Remova argumentos vazios antes de salvar ou executar a acao.',
            },
          ),
        );
      }
      if (argument.length > AgentActionExecutableConstants.maxArgumentLength) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Executable action argument exceeds the allowed length.',
            context: {
              'action_id': actionId,
            'field': field,
            'phase': phase,
            'argument_index': index,
            'max_argument_length': AgentActionExecutableConstants.maxArgumentLength,
              'reason': AgentActionExecutableConstants.argumentTooLongReason,
              'user_message': 'Um dos argumentos configurados e longo demais para esta acao.',
            },
          ),
        );
      }

      normalizedArguments.add(argument);
    }

    return Success(normalizedArguments);
  }

  String? _extensionOf(String path) {
    final lastSeparator = path.lastIndexOf(RegExp(r'[\\/]'));
    final fileName = lastSeparator >= 0 ? path.substring(lastSeparator + 1) : path;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) {
      return null;
    }

    return fileName.substring(dotIndex).toLowerCase();
  }

  String _fileNameOf(String path) {
    final lastSeparator = path.lastIndexOf(RegExp(r'[\\/]'));
    return lastSeparator >= 0 ? path.substring(lastSeparator + 1) : path;
  }

  String _buildRedactedProcessPreview({
    required String executable,
    required List<String> redactedArguments,
    List<String> prefixArguments = const <String>[],
    String labelSuffix = '',
  }) {
    final previewArguments = <String>[
      ...prefixArguments,
      for (var index = 0; index < redactedArguments.length; index++) '[REDACTED_ARG_$index]',
    ];
    return '${WindowsCommandLineQuoter.joinArguments(<String>[executable, ...previewArguments])}$labelSuffix';
  }

  ActionValidationFailure? _rejectDisallowedArgumentCharacters({
    required String actionId,
    required String field,
    required String argument,
    required int argumentIndex,
    required String phase,
  }) {
    for (var index = 0; index < argument.length; index++) {
      final codeUnit = argument.codeUnitAt(index);
      if (codeUnit == 0x0A || codeUnit == 0x0D || codeUnit == 0x00) {
        return ActionValidationFailure.withContext(
          message: 'Executable action argument contains disallowed control characters.',
          context: {
            'action_id': actionId,
            'field': field,
            'phase': phase,
            'argument_index': argumentIndex,
            'reason': AgentActionExecutableConstants.invalidArgumentCharactersReason,
            'user_message': 'Remova quebras de linha ou caracteres de controle dos argumentos configurados.',
          },
        );
      }
    }

    return null;
  }
}
