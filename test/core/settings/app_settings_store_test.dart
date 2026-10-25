import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/settings/app_settings_keys.dart';
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

    for (final content in ['{invalid-json', '[]', '']) {
      test('preserves invalid settings and blocks overwrites: $content', () async {
        await File(settingsPath).writeAsString(content);
        final store = GlobalAppSettingsStore(filePath: settingsPath);
        await store.initialize();
        expect(store.readIntegrityError, isA<FormatException>());
        await expectLater(store.setBool(AppSettingsKeys.startWithWindows, true), throwsFormatException);
        await expectLater(store.flushPendingPersistence(), throwsFormatException);
        expect(await File(settingsPath).readAsString(), content);
      });
    }

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
