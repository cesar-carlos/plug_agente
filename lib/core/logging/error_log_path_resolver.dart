import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/error_log_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';

class ErrorLogAccessException implements Exception {
  const ErrorLogAccessException({
    required this.message,
    required this.attempts,
  });

  final String message;
  final List<String> attempts;

  @override
  String toString() {
    if (attempts.isEmpty) {
      return message;
    }
    return '$message Attempts: ${attempts.join(' | ')}';
  }
}

class ErrorLogPathResolver {
  ErrorLogPathResolver._();

  static String resolveFromGlobalStorage(GlobalStorageContext context) {
    return p.join(
      context.appDirectoryPath,
      ErrorLogConstants.logsSubdirectory,
    );
  }

  static Future<String> resolveWritableLogDirectory({
    List<String>? candidateDirectories,
  }) async {
    final candidates = candidateDirectories ?? _buildEarlyCandidateDirectories();
    final failures = <String>[];

    for (final candidate in candidates) {
      try {
        await _ensureWritableDirectory(candidate);
        return candidate;
      } on FileSystemException catch (error) {
        failures.add('$candidate -> ${error.message}');
      } on Exception catch (error) {
        failures.add('$candidate -> $error');
      }
    }

    throw ErrorLogAccessException(
      message: 'Unable to access a writable directory for error logs.',
      attempts: failures,
    );
  }

  static List<String> _buildEarlyCandidateDirectories() {
    if (!Platform.isWindows) {
      return <String>[
        p.join(
          Directory.systemTemp.path,
          GlobalStoragePathResolver.defaultAppFolderName,
          ErrorLogConstants.logsSubdirectory,
        ),
      ];
    }

    final candidates = <String>[];
    final seen = <String>{};

    void addCandidate(String? value) {
      if (value == null || value.isEmpty) {
        return;
      }
      final normalized = p.normalize(value);
      if (seen.add(normalized)) {
        candidates.add(normalized);
      }
    }

    final tempRoot = Platform.environment['TEMP'] ?? Directory.systemTemp.path;
    addCandidate(
      p.join(tempRoot, GlobalStoragePathResolver.defaultAppFolderName, ErrorLogConstants.logsSubdirectory),
    );

    final programData = Platform.environment['ProgramData'] ?? Platform.environment['ALLUSERSPROFILE'];
    addCandidate(
      programData == null
          ? null
          : p.join(programData, GlobalStoragePathResolver.defaultAppFolderName, ErrorLogConstants.logsSubdirectory),
    );

    return candidates;
  }

  static Future<void> _ensureWritableDirectory(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final probeFile = File(
      p.join(
        directoryPath,
        '.probe_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );

    try {
      await probeFile.writeAsString('ok', flush: true);
    } finally {
      if (probeFile.existsSync()) {
        await probeFile.delete();
      }
    }
  }
}
