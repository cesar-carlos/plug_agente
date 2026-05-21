import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/src/e2e_monorepo_env_paths.dart';

void main() {
  test('should prefer plug_server .env in monorepo layout', () {
    final mono = Directory.systemTemp.createTempSync('e2e_mono_paths_');
    addTearDown(() {
      if (mono.existsSync()) {
        mono.deleteSync(recursive: true);
      }
    });

    final agentRoot = Directory(p.join(mono.path, 'plug_agente'))..createSync();
    final serverRoot = Directory(p.join(mono.path, 'plug_server'))..createSync();
    final envPath = p.join(serverRoot.path, '.env');
    File(envPath).writeAsStringSync('E2E_HUB_URL=https://hub/agents\n');

    final candidates = siblingHubEnvFileCandidates(agentRoot.path);
    expect(candidates, contains(p.normalize(envPath)));
  });
}
