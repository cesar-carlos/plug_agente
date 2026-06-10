import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/backup/backup_zip_encoder.dart';

void main() {
  test('encodeBackupZipBytes builds a readable ZIP with optional secrets blob', () {
    final zip = encodeBackupZipBytes(
      BackupZipEncodeParts(
        manifestBytes: Uint8List.fromList([1, 2, 3]),
        dbBytes: Uint8List.fromList([4, 5, 6]),
        settingsBytes: Uint8List.fromList([7, 8]),
        secureStorageSecretsBytes: Uint8List.fromList([9, 10]),
        secureStorageSecretsFileName: 'secure_storage_secrets.enc',
      ),
    )!;

    final decoded = ZipDecoder().decodeBytes(zip);
    final names = decoded.files.where((f) => f.isFile).map((f) => f.name).toSet();
    expect(names, containsAll(<String>['manifest.json', 'agent_config.db', 'settings.json', 'secure_storage_secrets.enc']));
  });
}
