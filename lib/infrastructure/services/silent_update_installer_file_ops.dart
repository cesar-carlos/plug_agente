import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// File naming, hashing, and artifact cleanup helpers for silent updates.
final class SilentUpdateInstallerFileOps {
  const SilentUpdateInstallerFileOps._();

  static String sanitizeFileName(String raw) {
    final sanitized = raw.trim().replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    if (sanitized.isEmpty) {
      return 'PlugAgente-Setup.exe';
    }
    return sanitized;
  }

  static void deleteIfExists(File file) {
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  /// Streams the file through SHA-256 instead of loading every byte
  /// into memory. Matters because installer payloads keep growing
  /// (runtime + bundled dependencies) and `readAsBytesSync` would
  /// allocate the whole thing on the heap *and* block the event loop.
  static Future<String> sha256OfStreaming(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Same as [sha256OfStreaming] but never throws — used for diagnostic
  /// fingerprints where measurement failure must not abort the install
  /// pipeline.
  static Future<String?> sha256OfFileBestEffort(File file) async {
    try {
      return await sha256OfStreaming(file);
    } on FileSystemException {
      return null;
    } on Exception {
      return null;
    }
  }

  static void cleanupFamily(
    Directory directory, {
    required String prefix,
    required int keepLatestCount,
    required Duration maxAge,
    String? excludePrefix,
  }) {
    final now = DateTime.now();
    final files = directory.listSync().whereType<File>().where((file) {
      final name = p.basename(file.path);
      return name.startsWith(prefix) && (excludePrefix == null || !name.startsWith(excludePrefix));
    }).toList()..sort((left, right) => right.lastModifiedSync().compareTo(left.lastModifiedSync()));
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      final isOld = now.difference(file.lastModifiedSync()) > maxAge;
      if (index >= keepLatestCount || isOld) {
        deleteIfExists(file);
      }
    }
  }
}
