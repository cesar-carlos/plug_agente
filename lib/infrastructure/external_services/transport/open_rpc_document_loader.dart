import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:plug_agente/core/logger/app_logger.dart';

/// Thrown when the OpenRPC document cannot be loaded from the asset bundle or
/// disk. Callers should surface this as an RPC error instead of advertising
/// zero methods.
class OpenRpcDocumentLoadException implements Exception {
  OpenRpcDocumentLoadException({
    required this.message,
    this.assetError,
    this.fileError,
    this.cwd,
  });

  final String message;
  final Object? assetError;
  final Object? fileError;
  final String? cwd;

  @override
  String toString() => 'OpenRpcDocumentLoadException: $message';
}

/// Loads the OpenRPC document used to answer `rpc.discover` requests.
///
/// Tries the asset bundle first, then the on-disk copy at
/// `<cwd>/docs/communication/openrpc.json`. On total failure, throws
/// [OpenRpcDocumentLoadException] so `rpc.discover` does not silently return
/// an empty method list.
///
/// Caches the first successful load so subsequent reads are O(1). The cache is
/// shared across all callers of [getDocument].
class OpenRpcDocumentLoader {
  OpenRpcDocumentLoader({
    Future<String> Function(String key)? assetLoader,
    Future<String> Function(String filePath)? fileLoader,
    String Function()? cwdProvider,
  }) : _assetLoader = assetLoader ?? rootBundle.loadString,
       _fileLoader = fileLoader ?? _defaultFileLoader,
       _cwdProvider = cwdProvider ?? _defaultCwdProvider;

  static const String _assetKey = 'docs/communication/openrpc.json';

  final Future<String> Function(String key) _assetLoader;
  final Future<String> Function(String filePath) _fileLoader;
  final String Function() _cwdProvider;

  Map<String, dynamic>? _cached;
  Future<Map<String, dynamic>>? _inFlight;

  /// Returns the cached document, the asset, or the disk copy. Concurrent
  /// callers share the same in-flight load.
  Future<Map<String, dynamic>> getDocument() {
    final cached = _cached;
    if (cached != null) {
      return Future.value(cached);
    }
    return _inFlight ??= _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      final content = await _assetLoader(_assetKey);
      final json = jsonDecode(content) as Map<String, dynamic>;
      _cached = json;
      return json;
    } on Object catch (assetError, assetStack) {
      try {
        final filePath = path.join(
          _cwdProvider(),
          'docs',
          'communication',
          'openrpc.json',
        );
        final content = await _fileLoader(filePath);
        final json = jsonDecode(content) as Map<String, dynamic>;
        _cached = json;
        return json;
      } on Object catch (fileError, fileStack) {
        final cwd = _cwdProvider();
        AppLogger.error(
          'Failed to load OpenRPC from asset bundle ($_assetKey)',
          assetError,
          assetStack,
        );
        AppLogger.error(
          'Failed to load OpenRPC from disk (cwd=$cwd/docs/communication/openrpc.json)',
          fileError,
          fileStack,
        );
        throw OpenRpcDocumentLoadException(
          message:
              'OpenRPC document unavailable from asset bundle and disk. '
              'Ensure docs/communication/openrpc.json is bundled in the app '
              'and available on disk for development.',
          assetError: assetError,
          fileError: fileError,
          cwd: cwd,
        );
      }
    } finally {
      _inFlight = null;
    }
  }

  static Future<String> _defaultFileLoader(String filePath) {
    return File(filePath).readAsString();
  }

  static String _defaultCwdProvider() => Directory.current.path;
}
