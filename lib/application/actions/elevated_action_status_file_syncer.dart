import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:plug_agente/application/actions/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/application/actions/elevated_action_status_file.dart';
import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/actions/i_agent_action_process_observer.dart';
import 'package:result_dart/result_dart.dart';

/// Reads elevated helper status JSON files and maps them to process results.
class ElevatedActionStatusFileSyncer {
  ElevatedActionStatusFileSyncer({
    required GlobalStorageContext storageContext,
    AgentActionExecutionMetricsCollector? metrics,
    DateTime Function()? now,
    IAgentActionProcessObserver? liveProcesses,
  }) : _storageContext = storageContext,
       _metrics = metrics,
       _now = now ?? DateTime.now,
       _liveProcesses = liveProcesses;

  final IAgentActionProcessObserver? _liveProcesses;
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
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final status = _parseStatus(Map<String, dynamic>.from(decoded));
      return status?.executionId == executionId.trim() ? status : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    } on Object catch (error, stackTrace) {
      developer.log(
        'Unexpected error reading elevated status file',
        name: 'elevated_action_status_file_syncer',
        error: error,
        stackTrace: stackTrace,
        level: 900,
      );
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
    Future<void>? abort,
  }) async {
    try {
      return await _waitForTerminalResult(
        executionId: executionId,
        processStartedAt: processStartedAt,
        timeout: timeout,
        abort: abort,
      );
    } finally {
      _liveProcesses?.finished(executionId);
    }
  }

  Future<Result<AgentActionProcessResult>> _waitForTerminalResult({
    required String executionId,
    required DateTime processStartedAt,
    required Duration timeout,
    Future<void>? abort,
  }) async {
    ElevatedActionStatusFile? latest;
    var published = false;
    var aborted = false;
    Object? abortError;
    if (abort != null) {
      unawaited(
        abort.then<void>(
          (_) {
            aborted = true;
          },
          onError: (Object error) {
            abortError = error;
            aborted = true;
          },
        ),
      );
    }
    final deadline = _now().add(timeout);
    while (_now().isBefore(deadline)) {
      final status = await tryReadStatus(executionId);
      if (status != null && !status.isTerminal && status.pid != null && _liveProcesses != null) {
        latest = status;
        if (!published) {
          final saved = await _liveProcesses.started(
            AgentActionLiveProcess(
              executionId: executionId,
              actionId: status.actionId!,
              pid: status.pid!,
              executable: status.processExecutable!,
              startedAt: status.processStartedAt!,
              cpuLimitPercent: status.cpuLimitPercent ?? 0,
              readCpu: () {
                final sample = latest;
                if (sample?.cpuMicroseconds == null ||
                    _now().difference(sample!.finishedAt).abs() > const Duration(seconds: 3)) {
                  return Failure(
                    ActionRuntimeFailure('A amostra de CPU do executor elevado está indisponível ou desatualizada.'),
                  );
                }
                return Success(Duration(microseconds: sample.cpuMicroseconds!));
              },
            ),
          );
          if (saved.isError()) return Failure(saved.exceptionOrNull()!);
          published = true;
        }
      }
      if (status != null && status.isTerminal) {
        await deleteStatusFile(executionId);
        _metrics?.recordElevatedStatusFileTerminalRead();
        return Success(_toProcessResult(status, processStartedAt));
      }

      if (abort == null) {
        await Future<void>.delayed(AgentActionElevatedConstants.statusPollInterval);
        continue;
      }

      await Future<void>.delayed(AgentActionElevatedConstants.statusPollInterval);
      if (aborted) {
        return Failure(
          ActionRuntimeFailure.withContext(
            message: 'Elevated execution was cancelled before completion.',
            code: AgentActionFailureCode.executionCancelled,
            cause: abortError,
            context: {
              'execution_id': executionId.trim(),
              'user_message': 'A execucao elevada foi cancelada.',
            },
          ),
        );
      }
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
      pid: status.pid ?? 0,
      processExecutable: status.processExecutable,
      processStartedAt: status.processStartedAt ?? processStartedAt,
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

    final pid = json['pid'];
    final actionId = json['actionId'];
    final executable = json['processExecutable'];
    final startedRaw = json['processStartedAt'];
    final started = startedRaw is String ? DateTime.tryParse(startedRaw) : null;
    final cpu = json['cpuMicroseconds'];
    final limit = json['cpuLimitPercent'];
    if (pid != null && (pid is! int || pid <= 0)) return null;
    if (cpu != null && (cpu is! int || cpu < 0)) return null;
    if (limit != null && (limit is! int || limit < 0 || limit > 100)) return null;
    if (!status.isTerminal &&
        (pid == null ||
            actionId is! String ||
            actionId.isEmpty ||
            executable is! String ||
            executable.isEmpty ||
            started == null)) {
      return null;
    }
    return ElevatedActionStatusFile(
      pid: pid as int?,
      actionId: actionId as String?,
      processExecutable: executable as String?,
      processStartedAt: started,
      cpuMicroseconds: cpu as int?,
      cpuLimitPercent: limit as int?,
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
