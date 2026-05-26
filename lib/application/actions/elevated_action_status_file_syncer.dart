import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/application/actions/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/application/actions/elevated_action_status_file.dart';
import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

/// Reads elevated helper status JSON files and maps them to process results.
class ElevatedActionStatusFileSyncer {
  ElevatedActionStatusFileSyncer({
    required GlobalStorageContext storageContext,
    AgentActionExecutionMetricsCollector? metrics,
    DateTime Function()? now,
  }) : _storageContext = storageContext,
       _metrics = metrics,
       _now = now ?? DateTime.now;

  final GlobalStorageContext _storageContext;
  final AgentActionExecutionMetricsCollector? _metrics;
  final DateTime Function() _now;

  Future<ElevatedActionStatusFile?> tryReadStatus(String executionId) async {
    final file = File(
      AgentActionElevatedConstants.statusFilePath(
        _storageContext.appDirectoryPath,
        executionId.trim(),
      ),
    );
    if (!file.existsSync()) {
      return null;
    }

    try {
      final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return _parseStatus(decoded);
    } on Object {
      return null;
    }
  }

  Future<Result<void>> deleteStatusFile(String executionId) async {
    final file = File(
      AgentActionElevatedConstants.statusFilePath(
        _storageContext.appDirectoryPath,
        executionId.trim(),
      ),
    );
    if (!file.existsSync()) {
      return const Success(unit);
    }

    try {
      await file.delete();
      return const Success(unit);
    } on IOException catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Unable to delete elevated status file after sync.',
          cause: error,
          context: {'execution_id': executionId.trim()},
        ),
      );
    }
  }

  Future<Result<AgentActionProcessResult>> waitForTerminalResult({
    required String executionId,
    required DateTime processStartedAt,
    required Duration timeout,
  }) async {
    final deadline = _now().add(timeout);
    while (_now().isBefore(deadline)) {
      final status = await tryReadStatus(executionId);
      if (status != null && status.isTerminal) {
        await deleteStatusFile(executionId);
        _metrics?.recordElevatedStatusFileTerminalRead();
        return Success(_toProcessResult(status, processStartedAt));
      }
      await Future<void>.delayed(AgentActionElevatedConstants.statusPollInterval);
    }

    _metrics?.recordElevatedStatusFileWaitTimeout();
    return Failure(
      ActionRuntimeFailure.withContext(
        message: 'Elevated execution timed out waiting for status file.',
        code: AgentActionFailureCode.executionTimedOut,
        context: {
          'execution_id': executionId.trim(),
          'user_message': 'A execucao elevada excedeu o tempo maximo aguardando o helper.',
        },
      ),
    );
  }

  AgentActionProcessResult _toProcessResult(
    ElevatedActionStatusFile status,
    DateTime processStartedAt,
  ) {
    return AgentActionProcessResult(
      status: status.status,
      pid: 0,
      processStartedAt: processStartedAt,
      finishedAt: status.finishedAt,
      exitCode: status.exitCode,
      processCommandPreview: status.processCommandPreview,
      stdout: status.stdoutText == null
          ? AgentActionCapturedOutput.disabled
          : AgentActionCapturedOutput(
              text: status.stdoutText!,
              isCaptured: true,
              isTruncated: status.stdoutTruncated,
            ),
      stderr: status.stderrText == null
          ? AgentActionCapturedOutput.disabled
          : AgentActionCapturedOutput(
              text: status.stderrText!,
              isCaptured: true,
              isTruncated: status.stderrTruncated,
            ),
      redactionApplied: status.redactionApplied,
      timedOut: status.status == AgentActionExecutionStatus.timedOut,
      killed: status.status == AgentActionExecutionStatus.killed,
      failureCode: status.failureCode,
      failureMessage: status.failureMessage,
    );
  }

  ElevatedActionStatusFile? _parseStatus(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! num || version.toInt() != AgentActionElevatedConstants.statusSchemaVersion) {
      return null;
    }
    final executionId = json['executionId'];
    final statusName = json['status'];
    final finishedAtRaw = json['finishedAt'];
    if (executionId is! String || statusName is! String || finishedAtRaw is! String) {
      return null;
    }

    final status = _parseExecutionStatus(statusName);
    if (status == null) {
      return null;
    }

    final finishedAt = DateTime.tryParse(finishedAtRaw);
    if (finishedAt == null) {
      return null;
    }

    return ElevatedActionStatusFile(
      executionId: executionId.trim(),
      status: status,
      finishedAt: finishedAt,
      redactionApplied: json['redactionApplied'] as bool? ?? true,
      exitCode: json['exitCode'] as int?,
      failureCode: json['failureCode'] as String?,
      failureMessage: json['failureMessage'] as String?,
      stdoutText: json['stdoutText'] as String?,
      stderrText: json['stderrText'] as String?,
      stdoutTruncated: json['stdoutTruncated'] as bool? ?? false,
      stderrTruncated: json['stderrTruncated'] as bool? ?? false,
      processCommandPreview: json['processCommandPreview'] as String?,
    );
  }

  AgentActionExecutionStatus? _parseExecutionStatus(String statusName) {
    for (final value in AgentActionExecutionStatus.values) {
      if (value.name == statusName) {
        return value;
      }
    }
    return null;
  }
}
