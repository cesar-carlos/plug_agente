import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/src/dot_env_patch.dart';

void main() {
  late Directory agentRoot;
  late Directory monorepoRoot;

  setUp(() {
    monorepoRoot = Directory.systemTemp.createTempSync('promote_signing_mono_');
    agentRoot = Directory(p.join(monorepoRoot.path, 'plug_agente'));
    agentRoot.createSync();
    Directory(p.join(monorepoRoot.path, 'plug_server')).createSync();
    File(p.join(monorepoRoot.path, 'plug_server', '.env')).writeAsStringSync('''
PAYLOAD_SIGNING_KEY_ID=hub-key-1
PAYLOAD_SIGNING_KEY=shared-secret
''');
    File(p.join(agentRoot.path, '.env')).writeAsStringSync('''
PAYLOAD_SIGNING_KEY_ID=
PAYLOAD_SIGNING_KEY=
''');
  });

  tearDown(() {
    if (monorepoRoot.existsSync()) {
      monorepoRoot.deleteSync(recursive: true);
    }
  });

  test('should patch agent .env from plug_server .env values', () {
    final serverEnv = _loadEnvFile(p.join(monorepoRoot.path, 'plug_server', '.env'));
    final keyId = serverEnv['PAYLOAD_SIGNING_KEY_ID']!;
    final key = serverEnv['PAYLOAD_SIGNING_KEY']!;

    expect(
      patchDotEnvKey(projectRoot: agentRoot.path, key: 'PAYLOAD_SIGNING_KEY_ID', value: keyId),
      isTrue,
    );
    expect(
      patchDotEnvKey(projectRoot: agentRoot.path, key: 'PAYLOAD_SIGNING_KEY', value: key),
      isTrue,
    );

    final agentEnv = _loadEnvFile(p.join(agentRoot.path, '.env'));
    expect(agentEnv['PAYLOAD_SIGNING_KEY_ID'], 'hub-key-1');
    expect(agentEnv['PAYLOAD_SIGNING_KEY'], 'shared-secret');
  });
}

Map<String, String> _loadEnvFile(String path) {
  final result = <String, String>{};
  for (final line in File(path).readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#') || !trimmed.contains('=')) {
      continue;
    }
    final idx = trimmed.indexOf('=');
    result[trimmed.substring(0, idx).trim()] = trimmed.substring(idx + 1).trim();
  }
  return result;
}
