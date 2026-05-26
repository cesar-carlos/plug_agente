import 'package:plug_agente/application/actions/agent_action_secret_placeholder_resolver.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_scanner.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

/// Builds the child-process environment from action policy and runtime injection rules.
class ActionEnvironmentResolver {
  const ActionEnvironmentResolver({
    AgentActionSecretPlaceholderResolver? secretPlaceholderResolver,
  }) : _secretPlaceholderResolver = secretPlaceholderResolver ?? const AgentActionSecretPlaceholderResolver();

  static final RegExp _variableNamePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  static const int _maxVariableValueLength = 32767;

  final AgentActionSecretPlaceholderResolver _secretPlaceholderResolver;

  bool resolveIncludeParentEnvironment({
    required AgentActionEnvironmentPolicy policy,
    String? operationalProfile,
  }) {
    final configured = policy.includeParentEnvironment;
    if (configured != null) {
      return configured;
    }

    final normalizedProfile = operationalProfile?.trim().toLowerCase();
    if (normalizedProfile == AgentActionGateConstants.prodOperationalProfileName) {
      return false;
    }

    return true;
  }

  ActionValidationFailure? validatePolicy({
    required String actionId,
    required AgentActionEnvironmentPolicy policy,
    String phase = AgentActionProcessConstants.definitionValidationPhase,
  }) {
    for (final name in policy.allowedVariableNames) {
      final failure = _validateVariableName(
        actionId: actionId,
        name: name,
        field: 'environment.allowedVariableNames',
        phase: phase,
      );
      if (failure != null) {
        return failure;
      }
    }

    for (final entry in policy.variables.entries) {
      final nameFailure = _validateVariableName(
        actionId: actionId,
        name: entry.key,
        field: 'environment.variables',
        phase: phase,
      );
      if (nameFailure != null) {
        return nameFailure;
      }

      final allowFailure = _validateVariableAllowed(
        actionId: actionId,
        name: entry.key.trim(),
        policy: policy,
        field: 'environment.variables',
        phase: phase,
      );
      if (allowFailure != null) {
        return allowFailure;
      }

      final valueFailure = _validateLiteralValue(
        actionId: actionId,
        name: entry.key.trim(),
        value: entry.value,
        field: 'environment.variables',
        phase: phase,
      );
      if (valueFailure != null) {
        return valueFailure;
      }
    }

    return null;
  }

  Future<Result<Map<String, String>>> resolveForProcess({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
    String phase = AgentActionProcessConstants.executionPreflightPhase,
  }) async {
    final policy = definition.policies.environment;
    final resolved = <String, String>{};

    for (final entry in policy.variables.entries) {
      final name = entry.key.trim();
      final nameFailure = _validateVariableName(
        actionId: definition.id,
        name: name,
        field: 'environment.variables',
        phase: phase,
      );
      if (nameFailure != null) {
        return Failure(nameFailure);
      }

      final allowFailure = _validateVariableAllowed(
        actionId: definition.id,
        name: name,
        policy: policy,
        field: 'environment.variables',
        phase: phase,
      );
      if (allowFailure != null) {
        return Failure(allowFailure);
      }

      final valueResult = await _secretPlaceholderResolver.resolveText(
        text: entry.value,
        actionId: definition.id,
        phase: phase,
      );
      if (valueResult.isError()) {
        return Failure(valueResult.exceptionOrNull()!);
      }

      final resolvedValue = valueResult.getOrThrow();
      final valueFailure = _validateResolvedValue(
        actionId: definition.id,
        name: name,
        value: resolvedValue,
        field: 'environment.variables',
        phase: phase,
      );
      if (valueFailure != null) {
        return Failure(valueFailure);
      }

      resolved[name] = resolvedValue;
    }

    if (definition.policies.context.injectionMode == AgentActionContextInjectionMode.environment) {
      for (final entry in request.runtimeParameters.entries) {
        final name = entry.key.trim();
        final nameFailure = _validateVariableName(
          actionId: definition.id,
          name: name,
          field: 'runtimeParameters',
          phase: phase,
        );
        if (nameFailure != null) {
          return Failure(nameFailure);
        }

        final allowFailure = _validateVariableAllowed(
          actionId: definition.id,
          name: name,
          policy: policy,
          field: 'runtimeParameters',
          phase: phase,
        );
        if (allowFailure != null) {
          return Failure(allowFailure);
        }

        final value = entry.value;
        if (value is! String) {
          return Failure(
            ActionValidationFailure.withContext(
              message: 'Runtime environment injection requires string values.',
              context: {
                'action_id': definition.id,
                'field': 'runtimeParameters.$name',
                'phase': phase,
                'injection_mode': AgentActionContextInjectionMode.environment.name,
                'reason': AgentActionValidationConstants.invalidEnvironmentVariableValueReason,
                'user_message': 'Parametros runtime usados como variaveis de ambiente devem ser texto.',
              },
            ),
          );
        }

        final valueResult = await _secretPlaceholderResolver.resolveText(
          text: value,
          actionId: definition.id,
          phase: phase,
        );
        if (valueResult.isError()) {
          return Failure(valueResult.exceptionOrNull()!);
        }

        final resolvedValue = valueResult.getOrThrow();
        final valueFailure = _validateResolvedValue(
          actionId: definition.id,
          name: name,
          value: resolvedValue,
          field: 'runtimeParameters',
          phase: phase,
        );
        if (valueFailure != null) {
          return Failure(valueFailure);
        }

        resolved[name] = resolvedValue;
      }
    }

    return Success(Map<String, String>.unmodifiable(resolved));
  }

  Map<String, String> redactForDiagnostics(Map<String, String> environment) {
    const redactor = AgentActionRedactor();
    return Map<String, String>.unmodifiable(
      environment.map(
        (String key, String value) => MapEntry(key, redactor.redactText(value)),
      ),
    );
  }

  static Set<String> collectSecretNamesFromPolicy(AgentActionEnvironmentPolicy policy) {
    final names = <String>{};
    for (final value in policy.variables.values) {
      names.addAll(AgentActionSecretPlaceholderScanner.collectFromText(value));
    }
    return Set<String>.unmodifiable(names);
  }

  ActionValidationFailure? _validateVariableName({
    required String actionId,
    required String name,
    required String field,
    required String phase,
  }) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      return ActionValidationFailure.withContext(
        message: 'Environment variable name cannot be blank.',
        context: {
          'action_id': actionId,
          'field': field,
          'phase': phase,
          'reason': AgentActionValidationConstants.invalidEnvironmentVariableNameReason,
          'user_message': 'Informe um nome valido para a variavel de ambiente.',
        },
      );
    }

    if (!_variableNamePattern.hasMatch(normalized)) {
      return ActionValidationFailure.withContext(
        message: 'Environment variable name is invalid.',
        context: {
          'action_id': actionId,
          'field': field,
          'variable_name': normalized,
          'phase': phase,
          'reason': AgentActionValidationConstants.invalidEnvironmentVariableNameReason,
          'user_message':
              'Use nomes de variavel de ambiente com letras, numeros e underscore, iniciando por letra ou underscore.',
        },
      );
    }

    return null;
  }

  ActionValidationFailure? _validateVariableAllowed({
    required String actionId,
    required String name,
    required AgentActionEnvironmentPolicy policy,
    required String field,
    required String phase,
  }) {
    if (policy.allowsVariableName(name)) {
      return null;
    }

    return ActionValidationFailure.withContext(
      message: 'Environment variable is not allowed by policy.',
      context: {
        'action_id': actionId,
        'field': field,
        'variable_name': name,
        'phase': phase,
        'reason': AgentActionValidationConstants.environmentVariableNotAllowedReason,
        'user_message': 'A variavel de ambiente nao esta na lista permitida desta acao.',
      },
    );
  }

  ActionValidationFailure? _validateLiteralValue({
    required String actionId,
    required String name,
    required String value,
    required String field,
    required String phase,
  }) {
    if (value.isEmpty) {
      return ActionValidationFailure.withContext(
        message: 'Environment variable value cannot be blank.',
        context: {
          'action_id': actionId,
          'field': '$field.$name',
          'phase': phase,
          'reason': AgentActionValidationConstants.invalidEnvironmentVariableValueReason,
          'user_message': 'Informe um valor para a variavel de ambiente ou use um placeholder de segredo.',
        },
      );
    }

    return null;
  }

  ActionValidationFailure? _validateResolvedValue({
    required String actionId,
    required String name,
    required String value,
    required String field,
    required String phase,
  }) {
    if (value.isEmpty) {
      return ActionValidationFailure.withContext(
        message: 'Resolved environment variable value is blank.',
        context: {
          'action_id': actionId,
          'field': '$field.$name',
          'phase': phase,
          'reason': AgentActionValidationConstants.invalidEnvironmentVariableValueReason,
          'user_message': 'O valor da variavel de ambiente ficou vazio apos resolver segredos.',
        },
      );
    }

    if (value.length > _maxVariableValueLength) {
      return ActionValidationFailure.withContext(
        message: 'Environment variable value exceeds maximum length.',
        context: {
          'action_id': actionId,
          'field': '$field.$name',
          'phase': phase,
          'max_length': _maxVariableValueLength,
          'reason': AgentActionValidationConstants.invalidEnvironmentVariableValueReason,
          'user_message': 'O valor da variavel de ambiente excede o tamanho maximo permitido.',
        },
      );
    }

    return null;
  }
}
