import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:win32/win32.dart' as win32;

/// Platform-specific path and security helpers for silent update installation.
final class SilentUpdateInstallerPlatform {
  const SilentUpdateInstallerPlatform._();

  static const Duration icaclsTimeout = Duration(seconds: 30);

  static Future<String> resolveDefaultDownloadDirectory() async {
    final context = await GlobalStoragePathResolver.resolveContext();
    return p.join(context.appDirectoryPath, 'updates');
  }

  static Future<String> resolveDefaultInstallDirectory() async {
    return File(Platform.resolvedExecutable).parent.path;
  }

  static Future<String> resolveDefaultUpdateHelperPath() async {
    return p.join(File(Platform.resolvedExecutable).parent.path, 'plug_update_helper.exe');
  }

  static int resolveCurrentProcessId() => pid;

  /// Resolves free disk space on the volume that hosts [directoryPath].
  ///
  /// On Windows uses `GetDiskFreeSpaceExW` via FFI; on other platforms or
  /// when the syscall fails returns `null` so the installer falls back to
  /// best-effort (skips the check). Returning `null` is intentionally
  /// distinct from `0` so a real "no space" answer can still block.
  static Future<int?> resolveDefaultDiskFreeSpace(String directoryPath) async {
    if (!Platform.isWindows) return null;
    final pathPtr = directoryPath.toNativeUtf16();
    final freeBytesAvailable = calloc<Uint64>();
    final totalNumberOfBytes = calloc<Uint64>();
    final totalNumberOfFreeBytes = calloc<Uint64>();
    try {
      final ok = win32.GetDiskFreeSpaceEx(
        pathPtr,
        freeBytesAvailable.cast(),
        totalNumberOfBytes.cast(),
        totalNumberOfFreeBytes.cast(),
      );
      if (ok == 0) return null;
      final available = freeBytesAvailable.value;
      if (available > 0) return available;
      final totalFree = totalNumberOfFreeBytes.value;
      return totalFree > 0 ? totalFree : 0;
    } on Object {
      return null;
    } finally {
      calloc.free(pathPtr);
      calloc.free(freeBytesAvailable);
      calloc.free(totalNumberOfBytes);
      calloc.free(totalNumberOfFreeBytes);
    }
  }

  static Future<String> hardenUpdateDirectoryBestEffort(String updateDirectory) async {
    if (!Platform.isWindows) {
      return 'skippedNotWindows';
    }

    final programData = Platform.environment['ProgramData'] ?? Platform.environment['ALLUSERSPROFILE'];
    if (programData == null || programData.isEmpty) {
      return 'skippedNoProgramData';
    }
    final normalizedUpdateDirectory = p.normalize(updateDirectory).toLowerCase();
    final normalizedProgramData = p.normalize(programData).toLowerCase();
    if (!p.isWithin(normalizedProgramData, normalizedUpdateDirectory) &&
        normalizedUpdateDirectory != normalizedProgramData) {
      return 'skippedNonGlobalDirectory';
    }

    final username = Platform.environment['USERNAME']?.trim() ?? '';
    final userDomain = Platform.environment['USERDOMAIN']?.trim() ?? '';
    if (username.isEmpty) {
      return 'skippedNoUser';
    }
    final account = userDomain.isEmpty ? username : '$userDomain\\$username';

    try {
      final result = await Process.run(
        'icacls',
        <String>[
          updateDirectory,
          '/inheritance:r',
          '/grant:r',
          '*S-1-5-18:(OI)(CI)F',
          '*S-1-5-32-544:(OI)(CI)F',
          '$account:(OI)(CI)M',
        ],
      ).timeout(icaclsTimeout);
      return result.exitCode == 0 ? 'restricted' : 'failed:${result.exitCode}';
    } on TimeoutException {
      return 'failedTimeout';
    } on ProcessException {
      return 'failedToStart';
    }
  }

  static Future<bool> canWriteToInstallDirectory(String installDirectory) async {
    final probeFile = File(
      p.join(
        installDirectory,
        '.plug_agente_update_probe_${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      probeFile.writeAsStringSync('probe');
      probeFile.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
