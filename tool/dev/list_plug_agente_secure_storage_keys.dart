// ignore_for_file: avoid_print

/// Lists secure storage key names (no values) for diagnostics.
library;

import 'dart:io';

import '../src/plug_agente_windows_secure_storage_reader.dart';

void main() {
  if (!Platform.isWindows) {
    print('[warn] Windows only.');
    exit(1);
  }
  final path = plugAgenteSecureStorageFilePath();
  print('path: $path');
  if (path == null || !File(path).existsSync()) {
    print('[info] file missing');
    exit(1);
  }
  try {
    final keys = readPlugAgenteWindowsSecureStorage().keys.toList()..sort();
    print('[ok] ${keys.length} keys:');
    for (final key in keys) {
      print('  - $key');
    }
  } on Object catch (error) {
    print('[fail] $error');
    exit(1);
  }
}
