import 'dart:io';

import 'package:test/test.dart';

import '../../tool/src/plug_agente_windows_secure_storage_reader.dart';

void main() {
  test('should resolve plug agente secure storage path on Windows', () {
    if (!Platform.isWindows) {
      return;
    }
    final path = plugAgenteSecureStorageFilePath();
    expect(path, isNotNull);
    expect(path, contains('com.se7esistemas'));
    expect(path, endsWith('flutter_secure_storage.dat'));
  });

  test('should read map when installed app secure storage exists', () {
    if (!Platform.isWindows) {
      return;
    }
    final path = plugAgenteSecureStorageFilePath();
    if (path == null || !File(path).existsSync()) {
      return;
    }
    final map = readPlugAgenteWindowsSecureStorage();
    expect(map, isA<Map<String, String>>());
  });
}
