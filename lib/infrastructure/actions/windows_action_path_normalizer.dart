import 'dart:io';

import 'package:flutter/foundation.dart';

/// Windows-specific path normalization for agent action validation and snapshot comparison.
abstract final class WindowsActionPathNormalizer {
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// Normalizes paths for stable equality checks (UNC, extended-length prefix, separators).
  static String normalizeForComparison(String path) {
    var normalized = path.trim().replaceAll(r'\', '/');

    if (normalized.startsWith('//?/UNC/')) {
      normalized = '//${normalized.substring(8)}';
    } else if (normalized.startsWith('//?/')) {
      normalized = normalized.substring(4);
    }

    if (normalized.startsWith('//') && !normalized.startsWith('///')) {
      normalized = normalized.replaceFirst('//', '');
    }

    while (normalized.endsWith('/') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    return normalized.toLowerCase();
  }

  /// Returns a path suitable for local `File`/`Directory` IO on Windows (extended-length when needed).
  static String forLocalIo(String path) {
    final trimmed = path.trim();
    if (!isWindows || trimmed.isEmpty) {
      return trimmed;
    }

    if (trimmed.startsWith(r'\\?\\')) {
      return trimmed;
    }

    if (trimmed.startsWith(r'\\')) {
      return r'\\?\UNC\' + trimmed.substring(2);
    }

    if (trimmed.length >= 240) {
      return r'\\?\' + trimmed;
    }

    return trimmed;
  }

  static Future<String> canonicalizeFile(String path) async {
    final ioPath = forLocalIo(path);
    try {
      return await File(ioPath).resolveSymbolicLinks();
    } on FileSystemException {
      return File(ioPath).absolute.path;
    }
  }

  static Future<String> canonicalizeDirectory(String path) async {
    final ioPath = forLocalIo(path);
    try {
      return await Directory(ioPath).resolveSymbolicLinks();
    } on FileSystemException {
      return Directory(ioPath).absolute.path;
    }
  }

  static bool fileExists(String path) => File(forLocalIo(path)).existsSync();

  static bool directoryExists(String path) => Directory(forLocalIo(path)).existsSync();

  static Future<int> fileLength(String path) => File(forLocalIo(path)).length();

  static Future<String> readText(String path) => File(forLocalIo(path)).readAsString();
}
