import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/agent_action_test_manifest.dart'
    show readAgentActionContractTestPaths, readAgentActionUiTestPaths, resolvePlugAgenteProjectRoot;

void main() {
  final projectRoot = resolvePlugAgenteProjectRoot();

  test('should resolve every contract manifest path to an existing test file', () {
    final paths = readAgentActionContractTestPaths(projectRoot);
    expect(paths, isNotEmpty);
    for (final path in paths) {
      expect(
        File('$projectRoot${Platform.pathSeparator}$path').existsSync(),
        isTrue,
        reason: 'contract manifest entry missing: $path',
      );
    }
  });

  test('should resolve every UI manifest path to an existing test file', () {
    final paths = readAgentActionUiTestPaths(projectRoot);
    expect(paths, isNotEmpty);
    for (final path in paths) {
      expect(
        File('$projectRoot${Platform.pathSeparator}$path').existsSync(),
        isTrue,
        reason: 'UI manifest entry missing: $path',
      );
    }
  });
}
