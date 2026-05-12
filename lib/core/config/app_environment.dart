import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnvironment {
  AppEnvironment._();

  static Future<void> loadOptional() async {
    final file = _resolveDotEnvFile();
    try {
      if (file != null && file.existsSync()) {
        dotenv.loadFromString(
          envString: file.readAsStringSync(),
          isOptional: true,
        );
        return;
      }
      await dotenv.load(isOptional: true);
    } on Object {
      await dotenv.load(isOptional: true);
    }
  }

  static String? get(String key) {
    final fromDotenv = _dotenvSnapshot()[key]?.trim();
    if (fromDotenv != null && fromDotenv.isNotEmpty) {
      return fromDotenv;
    }

    final fromProcess = Platform.environment[key]?.trim();
    if (fromProcess != null && fromProcess.isNotEmpty) {
      return fromProcess;
    }

    return null;
  }

  static Map<String, String> snapshot() {
    return <String, String>{
      ...Platform.environment,
      ..._dotenvSnapshot(),
    };
  }

  static Map<String, String> _dotenvSnapshot() {
    try {
      return dotenv.env;
    } on Object {
      return const <String, String>{};
    }
  }

  static File? _resolveDotEnvFile() {
    for (final directory in _candidateDirectories()) {
      final file = File('${directory.path}${Platform.pathSeparator}.env');
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }

  static Iterable<Directory> _candidateDirectories() sync* {
    var current = Directory.current;
    for (var i = 0; i < 12; i++) {
      yield current;
      final pubspec = File('${current.path}${Platform.pathSeparator}pubspec.yaml');
      if (pubspec.existsSync()) {
        break;
      }
      final parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }

    final executable = Platform.resolvedExecutable;
    if (executable.isNotEmpty) {
      yield File(executable).parent;
    }
  }
}
