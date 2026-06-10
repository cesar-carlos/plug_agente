import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Serializable payload for ZIP encoding across isolates.
class BackupZipEncodeParts {
  const BackupZipEncodeParts({
    required this.manifestBytes,
    required this.dbBytes,
    this.settingsBytes,
    this.secureStorageSecretsBytes,
    this.secureStorageSecretsFileName,
  });

  final Uint8List manifestBytes;
  final Uint8List dbBytes;
  final Uint8List? settingsBytes;
  final Uint8List? secureStorageSecretsBytes;
  final String? secureStorageSecretsFileName;
}

/// Top-level ZIP builder for backup export; returns null if encoding fails.
Uint8List? encodeBackupZipBytes(BackupZipEncodeParts parts) {
  final archive = Archive()
    ..addFile(ArchiveFile('manifest.json', parts.manifestBytes.length, parts.manifestBytes))
    ..addFile(ArchiveFile('agent_config.db', parts.dbBytes.length, parts.dbBytes));
  if (parts.settingsBytes != null) {
    final s = parts.settingsBytes!;
    archive.addFile(ArchiveFile('settings.json', s.length, s));
  }
  if (parts.secureStorageSecretsBytes != null && parts.secureStorageSecretsFileName != null) {
    final secrets = parts.secureStorageSecretsBytes!;
    archive.addFile(
      ArchiveFile(parts.secureStorageSecretsFileName!, secrets.length, secrets),
    );
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    return null;
  }
  return Uint8List.fromList(encoded);
}
