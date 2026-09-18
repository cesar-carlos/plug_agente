import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/actions/i_agent_action_secret_placeholder_resolver.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_failure_cause.dart';
import 'package:result_dart/result_dart.dart';

/// Configures child-process stdin: closed by default, or payload when injection mode is stdin.
class ActionProcessStdinSetup {
  const ActionProcessStdinSetup({
    required IAgentActionSecretPlaceholderResolver secretPlaceholderResolver,
    this.stdinIoTimeout = defaultStdinIoTimeout,
  }) : _secretPlaceholderResolver = secretPlaceholderResolver;

  static const Duration defaultStdinIoTimeout = Duration(seconds: 10);

  final IAgentActionSecretPlaceholderResolver _secretPlaceholderResolver;
  final Duration stdinIoTimeout;

  Future<Result<void>> configure({
    required Process process,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
    required String actionId,
    Map<String, Object?> diagnostics = const {},
    String phase = AgentActionProcessConstants.executionPreflightPhase,
    Duration? ioTimeout,
  }) async {
    final effectiveTimeout = _effectiveTimeout(ioTimeout);
    if (effectiveTimeout <= Duration.zero) {
      return Failure(
        _timeoutFailure(
          actionId: actionId,
          diagnostics: diagnostics,
          phase: phase,
          reason: AgentActionProcessConstants.stdinCloseFailedReason,
        ),
      );
    }
    if (definition.policies.context.injectionMode != AgentActionContextInjectionMode.stdin) {
      return _closeStdin(
        actionId: actionId,
        process: process,
        diagnostics: diagnostics,
        timeout: effectiveTimeout,
      );
    }

    final rawPayload = request.runtimeParameters[AgentActionProcessConstants.stdinRuntimeParameterKey];
    if (rawPayload is! String || rawPayload.trim().isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Stdin injection requires a non-empty runtime stdin payload.',
          context: {
            'action_id': actionId,
            'field': 'runtimeParameters.${AgentActionProcessConstants.stdinRuntimeParameterKey}',
            'phase': phase,
            'injection_mode': AgentActionContextInjectionMode.stdin.name,
            'reason': AgentActionValidationConstants.contextInjectionRequiresStdinPayloadReason,
            'user_message': 'Informe o texto de entrada padrao em runtimeParameters.stdin antes de executar.',
          },
        ),
      );
    }

    final resolvedPayloadResult = await _secretPlaceholderResolver.resolveText(
      text: rawPayload,
      actionId: actionId,
      phase: phase,
    );
    if (resolvedPayloadResult.isError()) {
      return Failure(resolvedPayloadResult.exceptionOrNull()!);
    }

    final resolvedPayload = resolvedPayloadResult.getOrThrow();
    final maxBytes = definition.policies.context.maxContextBytes;
    final encoded = utf8.encode(resolvedPayload);
    if (encoded.length > maxBytes) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Stdin payload exceeds the maximum allowed context size.',
          context: {
            'action_id': actionId,
            'field': 'runtimeParameters.${AgentActionProcessConstants.stdinRuntimeParameterKey}',
            'phase': phase,
            'max_bytes': maxBytes,
            'actual_bytes': encoded.length,
            'reason': AgentActionPathContextConstants.contextFileTooLargeReason,
            'user_message': 'O conteudo enviado para stdin excede o limite configurado da acao.',
          },
        ),
      );
    }

    try {
      process.stdin.add(encoded);
      await process.stdin.flush().timeout(effectiveTimeout);
      await process.stdin.close().timeout(effectiveTimeout);
      return const Success(unit);
    } on TimeoutException catch (error) {
      return Failure(
        ActionTimeoutFailure.withContext(
          message: 'Timed out writing stdin payload to the child process.',
          cause: AgentActionProcessFailureCause.fromException(
            phase: 'stdin_setup',
            error: error,
          ),
          code: AgentActionFailureCode.executionTimedOut,
          context: {
            'action_id': actionId,
            ...diagnostics,
            'phase': 'stdin_setup',
            'pid': process.pid,
            'payload_bytes': encoded.length,
            'timeout_ms': effectiveTimeout.inMilliseconds,
            'reason': AgentActionProcessConstants.stdinWriteFailedReason,
            'user_message': 'O processo nao leu a entrada padrao a tempo. A execucao foi interrompida.',
          },
        ),
      );
    } on Exception catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Failed to write stdin payload to the child process.',
          cause: AgentActionProcessFailureCause.fromException(
            phase: 'stdin_setup',
            error: error,
          ),
          context: {
            'action_id': actionId,
            ...diagnostics,
            'phase': 'stdin_setup',
            'pid': process.pid,
            'payload_bytes': encoded.length,
            'reason': AgentActionProcessConstants.stdinWriteFailedReason,
            'user_message': 'Nao foi possivel enviar o conteudo para a entrada padrao do processo.',
          },
        ),
      );
    }
  }

  Future<Result<void>> _closeStdin({
    required String actionId,
    required Process process,
    required Map<String, Object?> diagnostics,
    required Duration timeout,
  }) async {
    try {
      await process.stdin.close().timeout(timeout);
      return const Success(unit);
    } on TimeoutException catch (error) {
      return Failure(
        ActionTimeoutFailure.withContext(
          message: 'Timed out closing process stdin.',
          cause: AgentActionProcessFailureCause.fromException(
            phase: 'stdin_setup',
            error: error,
          ),
          code: AgentActionFailureCode.executionTimedOut,
          context: {
            'action_id': actionId,
            ...diagnostics,
            'phase': 'stdin_setup',
            'pid': process.pid,
            'timeout_ms': timeout.inMilliseconds,
            'reason': AgentActionProcessConstants.stdinCloseFailedReason,
            'user_message': 'Nao foi possivel preparar a entrada padrao do processo a tempo.',
          },
        ),
      );
    } on Exception catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Failed to close process stdin.',
          cause: AgentActionProcessFailureCause.fromException(
            phase: 'stdin_setup',
            error: error,
          ),
          context: {
            'action_id': actionId,
            ...diagnostics,
            'phase': 'stdin_setup',
            'pid': process.pid,
            'reason': AgentActionProcessConstants.stdinCloseFailedReason,
            'user_message': 'Nao foi possivel preparar a entrada padrao do processo.',
          },
        ),
      );
    }
  }

  Duration _effectiveTimeout(Duration? requested) {
    if (requested == null || requested > stdinIoTimeout) {
      return stdinIoTimeout;
    }
    return requested;
  }

  ActionTimeoutFailure _timeoutFailure({
    required String actionId,
    required Map<String, Object?> diagnostics,
    required String phase,
    required String reason,
  }) {
    return ActionTimeoutFailure.withContext(
      message: 'The execution deadline elapsed before process stdin setup.',
      code: AgentActionFailureCode.executionTimedOut,
      context: {
        'action_id': actionId,
        ...diagnostics,
        'phase': phase,
        'reason': reason,
        'user_message': 'O tempo maximo da execucao foi atingido antes de preparar a entrada padrao.',
      },
    );
  }
}
