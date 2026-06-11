import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/services/silent_update_installer_file_ops.dart';

void main() {
  group('SilentUpdateInstallerFileOps', () {
    test('sanitizeFileName replaces unsafe characters', () {
      expect(
        SilentUpdateInstallerFileOps.sanitizeFileName('bad<>name.exe'),
        'bad__name.exe',
      );
      expect(SilentUpdateInstallerFileOps.sanitizeFileName('   '), 'PlugAgente-Setup.exe');
    });

    test('sha256OfStreaming matches digest of file contents', () async {
      final directory = Directory.systemTemp.createTempSync('silent_update_file_ops_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/payload.bin')..writeAsBytesSync(utf8.encode('hello'));
      final digest = await SilentUpdateInstallerFileOps.sha256OfStreaming(file);
      expect(digest, sha256.convert(utf8.encode('hello')).toString());
    });

    test('cleanupFamily keeps newest files and deletes old ones', () {
      final directory = Directory.systemTemp.createTempSync('silent_update_cleanup_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final older = File('${directory.path}/PlugAgente-Setup-old.log')
        ..writeAsStringSync('old')
        ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 40)));
      final newer = File('${directory.path}/PlugAgente-Setup-new.log')..writeAsStringSync('new');

      SilentUpdateInstallerFileOps.cleanupFamily(
        directory,
        prefix: 'PlugAgente-Setup-',
        keepLatestCount: 1,
        maxAge: const Duration(days: 30),
      );

      expect(older.existsSync(), isFalse);
      expect(newer.existsSync(), isTrue);
    });
  });
}
