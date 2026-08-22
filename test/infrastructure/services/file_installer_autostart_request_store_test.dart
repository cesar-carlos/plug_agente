import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/autostart_install_request_constants.dart';
import 'package:plug_agente/infrastructure/services/file_installer_autostart_request_store.dart';

void main() {
  group('FileInstallerAutostartRequestStore', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('autostart_request_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should report and clear a pending installer request', () async {
      final marker = File(
        p.join(tempDir.path, AutostartInstallRequestConstants.markerFileName),
      );
      await marker.writeAsString('1');
      final store = FileInstallerAutostartRequestStore(directoryPath: tempDir.path);

      expect(await store.hasPendingRequest(), isTrue);
      await store.clearPendingRequest();
      expect(await store.hasPendingRequest(), isFalse);
      expect(marker.existsSync(), isFalse);
    });

    test('should treat a missing marker as no pending request', () async {
      final store = FileInstallerAutostartRequestStore(directoryPath: tempDir.path);

      expect(await store.hasPendingRequest(), isFalse);
      await store.clearPendingRequest();
    });
  });
}
