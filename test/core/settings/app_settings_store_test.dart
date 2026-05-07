import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/settings/app_settings_store.dart';

void main() {
  group('GlobalAppSettingsStore', () {
    late Directory tempDir;
    late String settingsPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'app_settings_store_test',
      );
      settingsPath = p.join(tempDir.path, 'settings.json');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should quarantine corrupted settings file and continue', () async {
      final corruptedFile = File(settingsPath);
      await corruptedFile.writeAsString('{invalid-json');

      final store = GlobalAppSettingsStore(filePath: settingsPath);
      await store.initialize();

      expect(store.getKeys(), isEmpty);
      expect(File(settingsPath).existsSync(), isFalse);

      final quarantinedFiles = tempDir
          .listSync()
          .whereType<File>()
          .where(
            (file) => p.basename(file.path).startsWith('settings.json.corrupt.'),
          )
          .toList();
      expect(quarantinedFiles, isNotEmpty);

      await store.setBool('settings.start_with_windows', true);
      expect(File(settingsPath).existsSync(), isTrue);
      expect(store.getBool('settings.start_with_windows'), isTrue);
    });

    test('should quarantine invalid root type and continue', () async {
      final invalidRootFile = File(settingsPath);
      await invalidRootFile.writeAsString('[]');

      final store = GlobalAppSettingsStore(filePath: settingsPath);
      await store.initialize();

      expect(store.getKeys(), isEmpty);
      expect(File(settingsPath).existsSync(), isFalse);
    });

    test('flushPendingPersistence waits for concurrent queued writes', () async {
      final store = GlobalAppSettingsStore(filePath: settingsPath);
      await store.initialize();

      unawaited(store.setString('race_key', 'first'));
      unawaited(store.setString('race_key', 'second'));

      await store.flushPendingPersistence();

      final decoded = jsonDecode(await File(settingsPath).readAsString()) as Map<String, dynamic>;
      expect(decoded['race_key'], 'second');
    });
  });
}
