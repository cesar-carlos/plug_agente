import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_path_normalizer.dart';
import 'package:win32/win32.dart';

/// Best-effort Windows validation that a PID still refers to the expected process image and start time.
abstract final class WindowsProcessIdentityVerifier {
  static const int _maxImagePathChars = 32768;

  /// Returns `null` when identity is confirmed or checks were skipped.
  ///
  /// Returns a conservative [ActionFailure] when the OS identity cannot be read or does not match.
  static ActionFailure? verify({
    required String executionId,
    required int pid,
    String? expectedExecutable,
    DateTime? expectedStartedAt,
  }) {
    if (!Platform.isWindows || pid <= 0) {
      return null;
    }

    final trimmedExecutable = expectedExecutable?.trim();
    final needsExecutable = trimmedExecutable != null && trimmedExecutable.isNotEmpty;
    final needsStartedAt = expectedStartedAt != null;
    if (!needsExecutable && !needsStartedAt) {
      return null;
    }

    final handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (handle == 0 || handle == INVALID_HANDLE_VALUE) {
      return _identityUnavailable(
        executionId: executionId,
        pid: pid,
        osErrorCode: GetLastError(),
      );
    }

    try {
      if (needsExecutable) {
        final imagePath = _queryImagePath(handle);
        if (imagePath == null) {
          return _identityUnavailable(executionId: executionId, pid: pid, osErrorCode: GetLastError());
        }
        if (!executablePathsMatch(trimmedExecutable, imagePath)) {
          return _identityMismatch(
            executionId: executionId,
            pid: pid,
            expectedExecutable: trimmedExecutable,
            actualExecutable: imagePath,
            mismatchField: 'executable',
          );
        }
      }

      if (needsStartedAt) {
        final creationTime = _queryCreationTimeUtc(handle);
        if (creationTime == null) {
          return _identityUnavailable(executionId: executionId, pid: pid, osErrorCode: GetLastError());
        }
        if (!startedAtMatches(
          expected: expectedStartedAt,
          actual: creationTime,
          tolerance: AgentActionProcessConstants.processIdentityStartedAtTolerance,
        )) {
          return _identityMismatch(
            executionId: executionId,
            pid: pid,
            expectedStartedAt: expectedStartedAt.toUtc().toIso8601String(),
            actualStartedAt: creationTime.toUtc().toIso8601String(),
            mismatchField: 'process_started_at',
          );
        }
      }

      return null;
    } finally {
      CloseHandle(handle);
    }
  }

  static bool executablePathsMatch(String expected, String actual) {
    final expectedTrim = expected.trim();
    final actualTrim = actual.trim();
    if (expectedTrim.isEmpty || actualTrim.isEmpty) {
      return expectedTrim.isEmpty;
    }

    final expectedNorm = WindowsActionPathNormalizer.normalizeForComparison(expectedTrim);
    final actualNorm = WindowsActionPathNormalizer.normalizeForComparison(actualTrim);
    if (expectedNorm == actualNorm) {
      return true;
    }

    final expectedBase = p.basename(expectedTrim).toLowerCase();
    final actualBase = p.basename(actualTrim).toLowerCase();
    if (expectedBase == actualBase) {
      if (!expectedTrim.contains(r'\') && !expectedTrim.contains('/')) {
        return true;
      }
      if (actualNorm.endsWith('/$expectedNorm') || actualNorm.endsWith(expectedNorm)) {
        return true;
      }
    }

    return false;
  }

  static bool startedAtMatches({
    required DateTime expected,
    required DateTime actual,
    required Duration tolerance,
  }) {
    return expected.toUtc().difference(actual.toUtc()).abs() <= tolerance;
  }

  static String? _queryImagePath(int handle) {
    final buffer = wsalloc(_maxImagePathChars);
    final size = calloc<Uint32>()..value = _maxImagePathChars;
    try {
      final ok = QueryFullProcessImageName(handle, 0, buffer, size) != 0;
      if (!ok) {
        return null;
      }
      return buffer.toDartString();
    } finally {
      calloc.free(size);
      free(buffer);
    }
  }

  static DateTime? _queryCreationTimeUtc(int handle) {
    final creation = calloc<FILETIME>();
    final exit = calloc<FILETIME>();
    final kernel = calloc<FILETIME>();
    final user = calloc<FILETIME>();
    try {
      final ok = GetProcessTimes(handle, creation, exit, kernel, user) != 0;
      if (!ok) {
        return null;
      }
      return _fileTimeToUtcDateTime(creation.ref);
    } finally {
      calloc.free(creation);
      calloc.free(exit);
      calloc.free(kernel);
      calloc.free(user);
    }
  }

  static DateTime _fileTimeToUtcDateTime(FILETIME fileTime) {
    final high = fileTime.dwHighDateTime;
    final low = fileTime.dwLowDateTime;
    final ticks = (high << 32) | low;
    return DateTime.utc(1601).add(Duration(microseconds: ticks ~/ 10));
  }

  static ActionRuntimeFailure _identityMismatch({
    required String executionId,
    required int pid,
    required String mismatchField,
    String? expectedExecutable,
    String? actualExecutable,
    String? expectedStartedAt,
    String? actualStartedAt,
  }) {
    return ActionRuntimeFailure.withContext(
      message: 'Action execution process identity does not match persisted metadata.',
      code: AgentActionFailureCode.processIdentityMismatch,
      context: {
        'execution_id': executionId,
        'pid': pid,
        'mismatch_field': mismatchField,
        ?expectedExecutable: 'expected_executable',
        ?actualExecutable: 'actual_executable',
        ?expectedStartedAt: 'expected_process_started_at',
        ?actualStartedAt: 'actual_process_started_at',
        'reason': AgentActionProcessConstants.processIdentityMismatchReason,
        'user_message': 'O processo ativo nao corresponde aos metadados salvos desta execucao.',
      },
    );
  }

  static ActionRuntimeFailure _identityUnavailable({
    required String executionId,
    required int pid,
    required int osErrorCode,
  }) {
    return ActionRuntimeFailure.withContext(
      message: 'Unable to verify action execution process identity before kill.',
      code: AgentActionFailureCode.processIdentityUnavailable,
      context: {
        'execution_id': executionId,
        'pid': pid,
        'os_error_code': osErrorCode,
        'reason': AgentActionProcessConstants.processIdentityUnavailableReason,
        'user_message':
            'Nao foi possivel confirmar a identidade do processo antes de finaliza-lo. Tente novamente ou aguarde o termino natural.',
      },
    );
  }
}
