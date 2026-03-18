import 'dart:io';

import 'package:path/path.dart' as p;

class GlobalStorageContext {
  const GlobalStorageContext({required this.appDirectoryPath});

  final String appDirectoryPath;

  String get settingsFilePath => p.join(appDirectoryPath, 'settings.json');

  String get databaseFilePath => p.join(appDirectoryPath, 'agent_config.db');
}

class GlobalStorageAccessException implements Exception {
  const GlobalStorageAccessException({
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

class GlobalStorageBootstrapException implements Exception {
  const GlobalStorageBootstrapException({
    required this.attempts,
    this.message =
        'Global storage initialization failed. '
        'Grant write permission to ProgramData or Public Documents.',
  });

  static const String code = 'BOOTSTRAP_GLOBAL_STORAGE_DENIED';

  final String message;
  final List<String> attempts;

  @override
  String toString() {
    final details = attempts.isEmpty ? 'n/a' : attempts.join(' ; ');
    return '$code: $message Details: $details';
  }
}

class GlobalStoragePathResolver {
  GlobalStoragePathResolver._();

  static const String defaultAppFolderName = 'PlugAgente';

  static Future<GlobalStorageContext> resolveContext({
    String appFolderName = defaultAppFolderName,
    List<String>? candidateDirectories,
  }) async {
    final appDirectoryPath = await resolveWritableAppDirectory(
      appFolderName: appFolderName,
      candidateDirectories: candidateDirectories,
    );
    return GlobalStorageContext(appDirectoryPath: appDirectoryPath);
  }

  static Future<String> resolveWritableAppDirectory({
    String appFolderName = defaultAppFolderName,
    List<String>? candidateDirectories,
  }) async {
    final candidates =
        candidateDirectories ?? _buildCandidateDirectories(appFolderName);
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

    throw GlobalStorageAccessException(
      message:
          'Unable to access a global writable directory for application data.',
      attempts: failures,
    );
  }

  static List<String> _buildCandidateDirectories(String appFolderName) {
    if (!Platform.isWindows) {
      return <String>[p.join(Directory.systemTemp.path, appFolderName)];
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

    final programData =
        Platform.environment['ProgramData'] ??
        Platform.environment['ALLUSERSPROFILE'];
    addCandidate(
      programData == null ? null : p.join(programData, appFolderName),
    );

    final allUsersProfile = Platform.environment['ALLUSERSPROFILE'];
    addCandidate(
      allUsersProfile == null ? null : p.join(allUsersProfile, appFolderName),
    );

    final publicRoot = Platform.environment['PUBLIC'];
    addCandidate(
      publicRoot == null
          ? null
          : p.join(publicRoot, 'Documents', appFolderName),
    );

    addCandidate(p.join(r'C:\ProgramData', appFolderName));
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
