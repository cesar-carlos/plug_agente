import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/src/dot_env_patch.dart';
import '../../tool/src/e2e_monorepo_env_paths.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('generate_dev_e2e_signing_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('should patch empty PAYLOAD_SIGNING keys in .env when onlyIfEmpty is true', () {
    File(p.join(tempDir.path, '.env')).writeAsStringSync(
      'PAYLOAD_SIGNING_KEY_ID=\nPAYLOAD_SIGNING_KEY=\nE2E_HUB_URL=https://hub/agents\n',
    );

    expect(
      patchDotEnvKey(projectRoot: tempDir.path, key: 'PAYLOAD_SIGNING_KEY_ID', value: 'e2e-dev'),
      isTrue,
    );
    expect(
      patchDotEnvKey(projectRoot: tempDir.path, key: 'PAYLOAD_SIGNING_KEY', value: 'secret-base64'),
      isTrue,
    );

    final content = File(p.join(tempDir.path, '.env')).readAsStringSync();
    expect(content, contains('PAYLOAD_SIGNING_KEY_ID=e2e-dev'));
    expect(content, contains('PAYLOAD_SIGNING_KEY=secret-base64'));
    expect(content, contains('E2E_HUB_URL=https://hub/agents'));
  });

  test('should patch sibling plug_server .env when monorepo layout exists', () {
    final mono = Directory.systemTemp.createTempSync('generate_dev_mono_');
    addTearDown(() {
      if (mono.existsSync()) {
        mono.deleteSync(recursive: true);
      }
    });
    final agentRoot = Directory(p.join(mono.path, 'plug_agente'))..createSync();
    final serverRoot = Directory(p.join(mono.path, 'plug_server'))..createSync();
    File(p.join(agentRoot.path, '.env')).writeAsStringSync(
      'PAYLOAD_SIGNING_KEY_ID=\nPAYLOAD_SIGNING_KEY=\n',
    );
    File(p.join(serverRoot.path, '.env')).writeAsStringSync(
      'PAYLOAD_SIGNING_KEY_ID=\nPAYLOAD_SIGNING_KEY=\n',
    );

    final hubPaths = siblingHubEnvFileCandidates(agentRoot.path);
    expect(hubPaths, isNotEmpty);

    for (final envPath in hubPaths) {
      final hubRoot = File(envPath).parent.path;
      expect(
        patchDotEnvKey(projectRoot: hubRoot, key: 'PAYLOAD_SIGNING_KEY_ID', value: 'e2e-dev'),
        isTrue,
      );
      expect(
        patchDotEnvKey(projectRoot: hubRoot, key: 'PAYLOAD_SIGNING_KEY', value: 'hub-secret'),
        isTrue,
      );
    }

    expect(
      File(p.join(serverRoot.path, '.env')).readAsStringSync(),
      allOf(contains('PAYLOAD_SIGNING_KEY_ID=e2e-dev'), contains('PAYLOAD_SIGNING_KEY=hub-secret')),
    );
  });

  test('should list sibling hub env when plug_server directory exists', () {
    final mono = Directory.systemTemp.createTempSync('generate_dev_hubdir_');
    addTearDown(() {
      if (mono.existsSync()) {
        mono.deleteSync(recursive: true);
      }
    });
    final agentRoot = Directory(p.join(mono.path, 'plug_agente'))..createSync();
    Directory(p.join(mono.path, 'plug_server')).createSync();

    expect(siblingHubEnvFileCandidates(agentRoot.path), isEmpty);
    expect(siblingHubProjectRoots(agentRoot.path), isNotEmpty);
  });

  test('should not overwrite existing signing keys', () {
    File(p.join(tempDir.path, '.env')).writeAsStringSync(
      'PAYLOAD_SIGNING_KEY_ID=prod-key\nPAYLOAD_SIGNING_KEY=existing\n',
    );

    expect(
      patchDotEnvKey(projectRoot: tempDir.path, key: 'PAYLOAD_SIGNING_KEY_ID', value: 'e2e-dev'),
      isFalse,
    );
    expect(
      File(p.join(tempDir.path, '.env')).readAsStringSync(),
      contains('PAYLOAD_SIGNING_KEY_ID=prod-key'),
    );
  });
}
