import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_path_normalizer.dart';

abstract final class AgentActionPathValidationHelpers {
  static String hashContent(String content) {
    return 'sha256:${sha256.convert(utf8.encode(content))}';
  }

  static String normalizePathForComparison(String path) =>
      WindowsActionPathNormalizer.normalizeForComparison(path);

  static bool allowsExtension({
    required String? extension,
    required Set<String> allowedExtensions,
  }) {
    if (allowedExtensions.isEmpty) {
      return true;
    }
    if (extension == null || extension.isEmpty) {
      return false;
    }

    final normalizedExtension = extension.trim().toLowerCase();
    return allowedExtensions.any((candidate) {
      final normalizedCandidate = candidate.trim().toLowerCase();
      if (normalizedCandidate.isEmpty) {
        return false;
      }
      final candidateWithDot = normalizedCandidate.startsWith('.') ? normalizedCandidate : '.$normalizedCandidate';
      return normalizedExtension == candidateWithDot;
    });
  }

  static bool hasNonBlankAllowlist(Set<String> allowedDirectories) {
    for (final directory in allowedDirectories) {
      if (directory.trim().isNotEmpty) {
        return true;
      }
    }

    return false;
  }

  static Future<DateTime?> fileLastModifiedUtc(String path) async {
    try {
      final ioPath = WindowsActionPathNormalizer.forLocalIo(path);
      return File(ioPath).lastModifiedSync().toUtc();
    } on FileSystemException {
      return null;
    }
  }

  static Future<bool> defaultFileExists(String path) =>
      Future<bool>.value(WindowsActionPathNormalizer.fileExists(path));

  static Future<bool> defaultDirectoryExists(String path) =>
      Future<bool>.value(WindowsActionPathNormalizer.directoryExists(path));

  static Future<String> defaultCanonicalizeFile(String path) => WindowsActionPathNormalizer.canonicalizeFile(path);

  static Future<String> defaultCanonicalizeDirectory(String path) =>
      WindowsActionPathNormalizer.canonicalizeDirectory(path);

  static Future<int> defaultFileLength(String path) => WindowsActionPathNormalizer.fileLength(path);

  static Future<String> defaultReadText(String path) => WindowsActionPathNormalizer.readText(path);
}
