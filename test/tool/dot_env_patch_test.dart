import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/src/dot_env_patch.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dot_env_patch_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('should patch empty key in .env when onlyIfEmpty is true', () {
    File(p.join(tempDir.path, '.env')).writeAsStringSync('E2E_HUB_URL=\nOTHER=value\n');

    final changed = patchDotEnvKey(
      projectRoot: tempDir.path,
      key: 'E2E_HUB_URL',
      value: 'https://hub.example.com/agents',
    );

    expect(changed, isTrue);
    final content = File(p.join(tempDir.path, '.env')).readAsStringSync();
    expect(content, contains('E2E_HUB_URL=https://hub.example.com/agents'));
    expect(content, contains('OTHER=value'));
  });

  test('should not overwrite non-empty key when onlyIfEmpty is true', () {
    File(p.join(tempDir.path, '.env')).writeAsStringSync('E2E_HUB_URL=https://existing/agents\n');

    final changed = patchDotEnvKey(
      projectRoot: tempDir.path,
      key: 'E2E_HUB_URL',
      value: 'https://new.example.com/agents',
    );

    expect(changed, isFalse);
    expect(
      File(p.join(tempDir.path, '.env')).readAsStringSync(),
      contains('E2E_HUB_URL=https://existing/agents'),
    );
  });
}
