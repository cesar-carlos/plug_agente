import 'dart:io';

import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('ElevatedActionRunnerReadinessService', () {
    late Directory tempDir;
    late GlobalStorageContext storageContext;
    late ElevatedActionRunnerReadinessService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('elevated_runner_readiness_test_');
      storageContext = GlobalStorageContext(appDirectoryPath: tempDir.path);
      service = ElevatedActionRunnerReadinessService();
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should report not configured when ready marker is absent', () {
      service.refresh(storageContext);

      expect(service.isConfigured, isFalse);
      expect(service.isDegraded, isFalse);
    });

    test('should report configured when ready marker exists', () async {
      final markerPath = AgentActionElevatedConstants.readyMarkerPath(tempDir.path);
      await File(markerPath).parent.create(recursive: true);
      await File(markerPath).writeAsString('ok');

      service.refresh(storageContext);

      expect(service.isConfigured, isTrue);
    });

    test('should track degraded state independently of configured marker', () {
      service.markDegraded(reason: 'helper_exit_1');

      expect(service.isDegraded, isTrue);
      expect(service.degradedReason, 'helper_exit_1');

      service.clearDegraded();

      expect(service.isDegraded, isFalse);
      expect(service.degradedReason, isNull);
    });
  });
}
