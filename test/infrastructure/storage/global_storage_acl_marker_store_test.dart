import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_acl_marker_store.dart';
import 'package:plug_agente/infrastructure/storage/icacls_grant_outcome.dart';

void main() {
  group('GlobalStorageAclMarkerStore', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('plug_agente_acl_marker_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should report fresh marker when app version matches', () async {
      final store = GlobalStorageAclMarkerStore(appVersionReader: () => '1.0.0+1');
      await store.write(
        appDirectoryPath: tempDir.path,
        outcome: const IcaclsGrantOutcome.success(),
      );

      expect(store.isFresh(tempDir.path), isTrue);
      expect(store.read(tempDir.path)?.appVersion, '1.0.0+1');
    });

    test('should report stale marker when app version changes', () async {
      var version = '1.0.0+1';
      final store = GlobalStorageAclMarkerStore(appVersionReader: () => version);
      await store.write(
        appDirectoryPath: tempDir.path,
        outcome: const IcaclsGrantOutcome.success(),
      );

      version = '2.0.0+1';
      expect(store.isFresh(tempDir.path), isFalse);
    });
  });
}
