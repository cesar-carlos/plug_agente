import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_acl_bootstrap.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_acl_marker_store.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_directory_acl_normalizer.dart';
import 'package:plug_agente/infrastructure/storage/icacls_command_runner.dart';
import 'package:plug_agente/infrastructure/storage/icacls_grant_outcome.dart';

void main() {
  group('GlobalStorageAclBootstrap', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('plug_agente_acl_bootstrap_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    GlobalStorageAclBootstrap buildBootstrap({void Function()? onNormalize}) {
      return GlobalStorageAclBootstrap(
        markerStore: GlobalStorageAclMarkerStore(appVersionReader: () => '1.0.0+1'),
        normalizer: GlobalStorageDirectoryAclNormalizer(
          commandRunner: IcaclsCommandRunner(
            processRunner: (executable, arguments) async {
              onNormalize?.call();
              return ProcessResult(0, 0, '', '');
            },
          ),
        ),
      );
    }

    test('should skip normalize when marker is fresh', () async {
      var normalizeCalls = 0;
      final markerStore = GlobalStorageAclMarkerStore(appVersionReader: () => '1.0.0+1');
      await markerStore.write(
        appDirectoryPath: tempDir.path,
        outcome: const IcaclsGrantOutcome.success(),
      );

      final bootstrap = GlobalStorageAclBootstrap(
        markerStore: markerStore,
        normalizer: GlobalStorageDirectoryAclNormalizer(
          commandRunner: IcaclsCommandRunner(
            processRunner: (executable, arguments) async {
              normalizeCalls++;
              return ProcessResult(0, 0, '', '');
            },
          ),
        ),
      );

      await bootstrap.ensureDirectoryAcls(tempDir.path);

      expect(normalizeCalls, 0);
    });

    test('should normalize and write marker when marker is missing', () async {
      var normalizeCalls = 0;
      final bootstrap = buildBootstrap(onNormalize: () => normalizeCalls++);

      await bootstrap.ensureDirectoryAcls(tempDir.path);

      if (Platform.isWindows) {
        expect(normalizeCalls, greaterThan(0));
        expect(bootstrap.markerStore.isFresh(tempDir.path), isTrue);
      }
    });
  });
}
