import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:plug_agente_elevated_runner/src/elevated_contract.dart';
import 'package:plug_agente_elevated_runner/src/elevated_output_reader.dart';
import 'package:plug_agente_elevated_runner/src/elevated_process_job.dart';
import 'package:windows_action_runtime/windows_action_runtime.dart';
import 'package:plug_agente_elevated_runner/src/elevated_launch_spec.dart';
import 'package:plug_agente_elevated_runner/src/elevated_materialized_reader.dart';
import 'package:plug_agente_elevated_runner/src/elevated_sqlite_store.dart';
import 'package:plug_agente_elevated_runner/src/elevated_status_writer.dart';

typedef ProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      bool runInShell,
    });

class ElevatedProcessRunner {
  ElevatedProcessRunner({
    required this.appDirectoryPath,
    ProcessStarter? processStarter,
    DateTime Function()? now,
    ElevatedStatusWriter? statusWriter,
    WindowsActionJobApi? jobApi,
  }) : _processStarter = processStarter ?? _defaultProcessStarter,
       _now = now ?? DateTime.now,
       _usesDefaultStarter = processStarter == null,
       _jobApi = jobApi,
       _statusWriter =
           statusWriter ??
           ElevatedStatusWriter(appDirectoryPath: appDirectoryPath);

  final bool _usesDefaultStarter;
  final WindowsActionJobApi? _jobApi;
  final ElevatedStatusWriter _statusWriter;
  final String appDirectoryPath;
  final ProcessStarter _processStarter;
  final DateTime Function() _now;

  Future<ElevatedStatusPayload> run({
    required ElevatedExecutionContext context,
    required ElevatedLaunchSpec launch,
    required String materializedNonce,
  }) async {
    if (context.definitionState != 'active') {
      return _failed(
        executionId: context.executionId,
        failureCode: 'ACTION_NOT_ACTIVE',
        failureMessage: 'Action is not active.',
      );
    }

    // Defense in depth: helper roda elevado mas so deve executar acoes cuja
    // policy declarou `elevated.runElevated=true`. Sem essa verificacao um
    // request forjado para uma acao nao elevada (com nonce/materialized
    // valido) seria executado com privilegios da tarefa.
    if (!_isElevationApproved(context.policies)) {
      return _failed(
        executionId: context.executionId,
        failureCode: 'ACTION_ELEVATED_NOT_CONFIGURED',
        failureMessage: 'Action policy did not approve elevated execution.',
      );
    }

    if (!ElevatedContract.supportedElevatedActionTypeNames.contains(
      context.actionType,
    )) {
      return _failed(
        executionId: context.executionId,
        failureCode: 'ACTION_UNSUPPORTED_FOR_ELEVATED_RUNNER',
        failureMessage: 'Action type is not supported by the elevated helper.',
      );
    }

    final maxRuntime = _readMaxRuntime(context.policies);
    final maxOutputBytes = _readMaxOutputBytes(context.policies);
    final acceptedExitCodes = _readAcceptedExitCodes(context.policies);
    final workingDirectory = _resolveWorkingDirectory(launch.workingDirectory);

    final startedAt = _now();
    Process? process;
    ElevatedProcessJob? job;
    ElevatedOutputReader? outputReader;
    ElevatedOutputReader? errorReader;
    final capture = context.policies['capture'];
    final captureStdout = capture is! Map || capture['captureStdout'] != false;
    final captureStderr = capture is! Map || capture['captureStderr'] != false;
    try {
      if (launch.cpuLimitPercent < 0 || launch.cpuLimitPercent > 100) {
        throw const FormatException('CPU limit must be between 0 and 100.');
      }
      final nativeStart = _usesDefaultStarter && Platform.isWindows;
      process = nativeStart
          ? await WindowsSilentActionProcess.start(
              launch.executable,
              launch.arguments,
              workingDirectory: workingDirectory,
              startSuspended: true,
              captureStdoutBytes: captureStdout ? maxOutputBytes : 0,
              captureStderrBytes: captureStderr ? maxOutputBytes : 0,
            )
          : await _processStarter(
              launch.executable,
              launch.arguments,
              workingDirectory: workingDirectory,
              runInShell: false,
            );

      outputReader = ElevatedOutputReader(
        process.stdout,
        enabled: captureStdout,
        maxBytes: maxOutputBytes,
      );
      errorReader = ElevatedOutputReader(
        process.stderr,
        enabled: captureStderr,
        maxBytes: maxOutputBytes,
      );
      if (_usesDefaultStarter && Platform.isWindows) {
        job = ElevatedProcessJob.attach(
          process.pid,
          launch.cpuLimitPercent,
          api: _jobApi,
        );
      } else if (launch.cpuLimitPercent > 0) {
        throw UnsupportedError('CPU limit requires a Windows process job.');
      }
      Future<void> publishRunning() => _statusWriter.write(
        ElevatedStatusPayload(
          executionId: context.executionId,
          actionId: context.actionId,
          status: 'running',
          finishedAt: _now(),
          pid: process!.pid,
          processExecutable: launch.executable,
          processStartedAt: startedAt,
          cpuMicroseconds: job?.readCpuMicroseconds(),
          cpuLimitPercent: launch.cpuLimitPercent,
        ),
      );
      await publishRunning();
      if (process is WindowsSilentActionProcess) process.resume();
      await process.stdin.close();
      final elapsed = Stopwatch()..start();
      var lastPublished = elapsed.elapsed;
      var timedOut = false;
      var cancelled = false;
      int? exitCode;
      Object? exitError;
      var exited = false;
      unawaited(
        process.exitCode.then<void>(
          (code) {
            exitCode = code;
            exited = true;
          },
          onError: (Object error) {
            exitError = error;
            exited = true;
          },
        ),
      );
      while (!exited && elapsed.elapsed < maxRuntime) {
        if (_isCancellationRequested(context.executionId, materializedNonce)) {
          cancelled = true;
          if (job != null) {
            job.terminate();
          } else {
            process.kill(ProcessSignal.sigkill);
          }
          exitCode = null;
          break;
        }

        if (elapsed.elapsed - lastPublished >= const Duration(seconds: 1)) {
          await publishRunning();
          lastPublished = elapsed.elapsed;
        }
        await Future<void>.delayed(ElevatedContract.pollInterval);
      }
      if (exitError != null)
        throw StateError('Unable to wait for action process: $exitError');

      if (!cancelled && exitCode == null) {
        timedOut = true;
        if (job != null) {
          job.terminate();
        } else {
          process.kill(ProcessSignal.sigkill);
        }
      }

      // Release the job before draining: descendants must not keep pipes alive.
      job?.close();
      job = null;
      final stdout = await outputReader.finish();
      final stderr = await errorReader.finish();
      final finishedAt = _now();
      final preview = launch.commandPreview;

      if (cancelled) {
        await _deleteCancelMarker(context.executionId);
        return ElevatedStatusPayload(
          executionId: context.executionId,
          pid: process.pid,
          processExecutable: launch.executable,
          processStartedAt: startedAt,
          status: 'killed',
          finishedAt: finishedAt,
          failureCode: 'ACTION_KILLED',
          failureMessage: 'Elevated execution was cancelled.',
          stdoutText: stdout.text,
          stderrText: stderr.text,
          stdoutTruncated: stdout.truncated,
          stderrTruncated: stderr.truncated,
          processCommandPreview: preview,
        );
      }

      if (timedOut) {
        return ElevatedStatusPayload(
          executionId: context.executionId,
          pid: process.pid,
          processExecutable: launch.executable,
          processStartedAt: startedAt,
          status: 'timedOut',
          finishedAt: finishedAt,
          failureCode: 'ACTION_EXECUTION_TIMED_OUT',
          failureMessage: 'Command exceeded the maximum runtime.',
          stdoutText: stdout.text,
          stderrText: stderr.text,
          stdoutTruncated: stdout.truncated,
          stderrTruncated: stderr.truncated,
          processCommandPreview: preview,
        );
      }

      final normalizedExitCode = exitCode ?? -1;
      final succeeded = acceptedExitCodes.contains(normalizedExitCode);
      return ElevatedStatusPayload(
        executionId: context.executionId,
        pid: process.pid,
        processExecutable: launch.executable,
        processStartedAt: startedAt,
        status: succeeded ? 'succeeded' : 'failed',
        finishedAt: finishedAt,
        exitCode: normalizedExitCode,
        failureCode: succeeded ? null : 'ACTION_EXIT_CODE_REJECTED',
        failureMessage: succeeded
            ? null
            : 'Command finished with exit code $normalizedExitCode.',
        stdoutText: stdout.text,
        stderrText: stderr.text,
        stdoutTruncated: stdout.truncated,
        stderrTruncated: stderr.truncated,
        processCommandPreview: preview,
      );
    } on Object catch (error) {
      if (process != null) {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode.timeout(const Duration(seconds: 5));
      }
      return _failed(
        executionId: context.executionId,
        failureCode: 'ACTION_RUNTIME_ERROR',
        failureMessage: 'Elevated process failed: $error',
      );
    } finally {
      try {
        job?.close();
      } finally {
        await outputReader?.dispose();
        await errorReader?.dispose();
      }
      await ElevatedMaterializedReader(
        appDirectoryPath: appDirectoryPath,
      ).delete(context.executionId);
    }
  }

  ElevatedStatusPayload _failed({
    required String executionId,
    required String failureCode,
    required String failureMessage,
  }) {
    return ElevatedStatusPayload(
      executionId: executionId,
      status: 'failed',
      finishedAt: _now(),
      failureCode: failureCode,
      failureMessage: failureMessage,
    );
  }

  bool _isElevationApproved(Map<String, dynamic> policies) {
    final elevated = policies['elevated'];
    if (elevated is Map) {
      return elevated['runElevated'] == true;
    }
    return false;
  }

  Duration _readMaxRuntime(Map<String, dynamic> policies) {
    final timeout = policies['timeout'];
    if (timeout is Map) {
      final maxRuntimeMs = timeout['maxRuntimeMs'];
      if (maxRuntimeMs is num && maxRuntimeMs > 0) {
        return Duration(milliseconds: maxRuntimeMs.toInt());
      }
    }
    return const Duration(minutes: 30);
  }

  int _readMaxOutputBytes(Map<String, dynamic> policies) {
    final capture = policies['capture'];
    if (capture is Map) {
      final maxBytes = capture['maxCapturedOutputBytes'];
      if (maxBytes is num && maxBytes > 0) {
        return maxBytes.toInt();
      }
    }
    return ElevatedContract.defaultMaxCapturedOutputBytes;
  }

  Set<int> _readAcceptedExitCodes(Map<String, dynamic> policies) {
    final exitCode = policies['exitCode'];
    if (exitCode is Map) {
      final values = exitCode['acceptedExitCodes'];
      if (values is List) {
        return values
            .whereType<num>()
            .map((num value) => value.toInt())
            .toSet();
      }
    }
    return <int>{0};
  }

  String? _resolveWorkingDirectory(String? workingDirectory) {
    if (workingDirectory == null || workingDirectory.trim().isEmpty) {
      return null;
    }
    final trimmed = workingDirectory.trim();
    if (Directory(trimmed).existsSync()) {
      return trimmed;
    }
    if (File(trimmed).parent.existsSync()) {
      return File(trimmed).parent.path;
    }
    return trimmed;
  }

  /// Verifies that a cancel marker exists AND echoes the materialized nonce.
  /// Without the nonce check, any local process with write access to the
  /// cancel directory could cancel arbitrary executions by dropping a JSON
  /// file. With the check, only the agent that knows the nonce (issued by
  /// the request protector) can effectively cancel.
  ///
  /// Legacy markers without a `nonce` field are accepted only when the
  /// materialized file is absent (helper already finished or app rolled back
  /// to legacy payloads). When materialized is present and the nonce field
  /// is missing or mismatched the cancel is ignored.
  bool _isCancellationRequested(String executionId, String materializedNonce) {
    final cancelFile = File(
      ElevatedContract.cancelFilePath(appDirectoryPath, executionId),
    );
    if (!cancelFile.existsSync()) {
      return false;
    }
    try {
      final decoded = jsonDecode(cancelFile.readAsStringSync());
      if (decoded is! Map) {
        return false;
      }
      final cancelNonce = decoded['nonce'];
      if (cancelNonce is String && cancelNonce.isNotEmpty) {
        return cancelNonce == materializedNonce;
      }
      // Legacy marker without nonce: only accepted when there is nothing to
      // protect (no live materialized nonce). Today the helper always has a
      // live nonce here because materialized survives until `finally` runs,
      // so legacy markers from the same window will be ignored. This is the
      // safest default.
      return false;
    } on Object {
      return false;
    }
  }

  Future<void> _deleteCancelMarker(String executionId) async {
    final file = File(
      ElevatedContract.cancelFilePath(appDirectoryPath, executionId),
    );
    try {
      if (file.existsSync()) {
        await file.delete();
      }
    } on Object {
      // Best effort cleanup.
    }
  }

  static Future<Process> _defaultProcessStarter(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  }) {
    return Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
  }
}
