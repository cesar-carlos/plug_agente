import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';

enum AgentActionCorrectiveActionKind {
  reviewPath('review_path'),
  reviewRunner('review_runner'),
  reviewExitCode('review_exit_code'),
  reviewQueue('review_queue'),
  reviewTimeout('review_timeout'),
  retryKill('retry_kill'),
  reviewDefinitionValidation('review_definition_validation'),
  reviewPreflight('review_preflight'),
  reviewStartProcess('review_start_process'),
  reviewRuntime('review_runtime'),
  ;

  const AgentActionCorrectiveActionKind(this.wireValue);

  final String wireValue;
}

class AgentActionFailureDiagnostics {
  const AgentActionFailureDiagnostics({
    this.failureCode,
    this.failurePhase,
    this.correctiveAction,
  });

  final String? failureCode;
  final String? failurePhase;
  final AgentActionCorrectiveActionKind? correctiveAction;
}

class AgentActionFailureDiagnosticsResolver {
  const AgentActionFailureDiagnosticsResolver();

  /// User-safe message for UI and scheduler surfaces.
  static String userMessage(Object failure) {
    if (failure is ActionFailure) {
      final userMessage = failure.context['user_message'];
      if (userMessage is String) {
        final trimmed = userMessage.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }

      return failure.message;
    }

    if (failure is Exception) {
      return failure.toString();
    }

    return failure.toString();
  }

  /// Minimal redacted diagnostics for the local definition test preview.
  Map<String, Object?> redactedDiagnosticsForTestPreview(ActionFailure failure) {
    final phase = failure.context['phase'];
    if (phase is! String) {
      return const <String, Object?>{};
    }

    final normalized = phase.trim();
    if (normalized.isEmpty) {
      return const <String, Object?>{};
    }

    return <String, Object?>{'phase': normalized};
  }

  AgentActionFailureDiagnostics resolve(AgentActionExecution execution) {
    return _resolveDiagnosticsValues(
      failureCode: execution.failureCode,
      failurePhase: execution.failurePhase,
    );
  }

  AgentActionFailureDiagnostics resolveFailure(ActionFailure failure) {
    final phase = failure.context['phase'];

    return _resolveDiagnosticsValues(
      failureCode: failure.code,
      failurePhase: phase is String ? phase : null,
    );
  }

  AgentActionFailureDiagnostics _resolveDiagnosticsValues({
    required String? failureCode,
    required String? failurePhase,
  }) {
    final normalizedFailureCode = _normalizeValue(failureCode);
    final normalizedFailurePhase = _normalizeValue(failurePhase);

    return AgentActionFailureDiagnostics(
      failureCode: normalizedFailureCode,
      failurePhase: normalizedFailurePhase,
      correctiveAction: _correctiveActionFor(
        failureCode: normalizedFailureCode,
        failurePhase: normalizedFailurePhase,
      ),
    );
  }

  AgentActionCorrectiveActionKind? _correctiveActionFor({
    required String? failureCode,
    required String? failurePhase,
  }) {
    final phasePreferred = _correctiveActionForExplicitPhase(
      failureCode: failureCode,
      failurePhase: failurePhase,
    );
    if (phasePreferred != null) {
      return phasePreferred;
    }

    switch (failureCode) {
      case AgentActionFailureCode.pathNotFound:
      case AgentActionFailureCode.contextPathNotFound:
      case AgentActionFailureCode.workingDirectoryNotFound:
      case AgentActionFailureCode.pathSnapshotMismatch:
      case AgentActionFailureCode.pathPermissionDenied:
        return AgentActionCorrectiveActionKind.reviewPath;
      case AgentActionFailureCode.runnerMissing:
      case AgentActionFailureCode.executableNotFound:
      case AgentActionFailureCode.interpreterNotFound:
      case AgentActionFailureCode.javaNotFound:
        return AgentActionCorrectiveActionKind.reviewRunner;
      case AgentActionFailureCode.exitCodeRejected:
        return AgentActionCorrectiveActionKind.reviewExitCode;
      case AgentActionFailureCode.queueFull:
      case AgentActionFailureCode.queueLimitReached:
      case AgentActionFailureCode.queueConcurrencyRejected:
      case AgentActionFailureCode.queueIgnored:
      case AgentActionFailureCode.queueCancelled:
      case AgentActionFailureCode.queueDisposed:
      case AgentActionFailureCode.queueItemNotFound:
        return AgentActionCorrectiveActionKind.reviewQueue;
      case AgentActionFailureCode.queueTimeout:
        return AgentActionCorrectiveActionKind.reviewTimeout;
      case AgentActionFailureCode.executionTimedOut:
        return AgentActionCorrectiveActionKind.reviewTimeout;
      case AgentActionFailureCode.killFailed:
        return AgentActionCorrectiveActionKind.retryKill;
      case AgentActionFailureCode.killPermissionDenied:
        return AgentActionCorrectiveActionKind.retryKill;
      case AgentActionFailureCode.lifecycleTriggerTimeout:
        return AgentActionCorrectiveActionKind.reviewTimeout;
      case AgentActionFailureCode.processNotActive:
      case AgentActionFailureCode.processIdMismatch:
      case AgentActionFailureCode.processIdentityMismatch:
      case AgentActionFailureCode.processIdentityUnavailable:
        return AgentActionCorrectiveActionKind.reviewStartProcess;
      case AgentActionFailureCode.runtimeError:
      case AgentActionFailureCode.runtimeUnknown:
      case AgentActionFailureCode.subsystemDegraded:
      case AgentActionFailureCode.subsystemStarting:
      case AgentActionFailureCode.subsystemDraining:
      case AgentActionFailureCode.interruptedOnBootstrap:
        return AgentActionCorrectiveActionKind.reviewRuntime;
      case AgentActionFailureCode.alreadyFinished:
      case AgentActionFailureCode.cancelNotRunning:
      case AgentActionFailureCode.executionCancelled:
      case AgentActionFailureCode.executionKilled:
      case AgentActionFailureCode.featureDisabled:
      case AgentActionFailureCode.maintenanceMode:
      case AgentActionFailureCode.subsystemReady:
        return null;
      case AgentActionFailureCode.remoteFeatureDisabled:
      case AgentActionFailureCode.remoteAdHocDisabled:
      case AgentActionFailureCode.elevatedDisabled:
      case AgentActionFailureCode.elevatedNotConfigured:
      case AgentActionFailureCode.elevatedRunnerDegraded:
      case AgentActionFailureCode.elevatedRequestProtectionFailed:
      case AgentActionFailureCode.elevatedSubmitFailed:
      case AgentActionFailureCode.unsupportedForElevatedRunner:
      case AgentActionFailureCode.schedulerBootstrapFailed:
      case AgentActionFailureCode.remoteNotApproved:
      case AgentActionFailureCode.remoteIdempotencyRequired:
      case AgentActionFailureCode.appCloseElevatedActionBlocked:
      case AgentActionFailureCode.appCloseRemoteActionBlocked:
      case AgentActionFailureCode.appCloseRuntimeTooLong:
      case AgentActionFailureCode.remoteApprovalAppCloseConflict:
      case AgentActionFailureCode.triggerActionIdBlank:
        return AgentActionCorrectiveActionKind.reviewDefinitionValidation;
    }

    return switch (failurePhase) {
      'definition_validation' => AgentActionCorrectiveActionKind.reviewDefinitionValidation,
      'validation' => AgentActionCorrectiveActionKind.reviewDefinitionValidation,
      AgentActionProcessConstants.bootstrapReconciliationPhase => AgentActionCorrectiveActionKind.reviewRuntime,
      'execution_preflight' => AgentActionCorrectiveActionKind.reviewPreflight,
      'start_process' => AgentActionCorrectiveActionKind.reviewStartProcess,
      'stdin_setup' => AgentActionCorrectiveActionKind.reviewStartProcess,
      'process_exit' => AgentActionCorrectiveActionKind.reviewExitCode,
      'process_runtime' => AgentActionCorrectiveActionKind.reviewRuntime,
      'timeout' => AgentActionCorrectiveActionKind.reviewTimeout,
      'cancel' => null,
      'elevated_submit' => AgentActionCorrectiveActionKind.reviewPreflight,
      'platform_check' => AgentActionCorrectiveActionKind.reviewDefinitionValidation,
      'smtp_send' => AgentActionCorrectiveActionKind.reviewRuntime,
      'execution_send' => AgentActionCorrectiveActionKind.reviewPreflight,
      'queue' => AgentActionCorrectiveActionKind.reviewQueue,
      'lookup' => AgentActionCorrectiveActionKind.reviewQueue,
      'authorization' => null,
      _ => null,
    };
  }

  AgentActionCorrectiveActionKind? _correctiveActionForExplicitPhase({
    required String? failureCode,
    required String? failurePhase,
  }) {
    final phase = failurePhase?.trim();
    if (phase == null || phase.isEmpty) {
      return null;
    }

    final isGenericRuntimeCode =
        failureCode == null ||
        failureCode == AgentActionFailureCode.runtimeError ||
        failureCode == AgentActionFailureCode.runtimeUnknown;
    if (!isGenericRuntimeCode) {
      return null;
    }

    return switch (phase) {
      'start_process' || 'stdin_setup' => AgentActionCorrectiveActionKind.reviewStartProcess,
      'execution_preflight' => AgentActionCorrectiveActionKind.reviewPreflight,
      'process_exit' => AgentActionCorrectiveActionKind.reviewExitCode,
      'process_runtime' => AgentActionCorrectiveActionKind.reviewRuntime,
      _ => null,
    };
  }

  String? _normalizeValue(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
