import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:plug_agente/core/constants/protocol_version.dart';
import 'package:plug_agente/core/logger/app_logger.dart';

/// Loads the OpenRPC document used to answer `rpc.discover` requests.
///
/// Tries the asset bundle first, then the on-disk copy at
/// `<cwd>/docs/communication/openrpc.json`, and finally returns a minimal
/// fallback so `rpc.discover` always succeeds.
///
/// Caches the first successful load (or the fallback) so subsequent reads are
/// O(1). The cache is shared across all callers of [getDocument].
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

  /// Returns the cached document, the asset, the disk copy, or the minimal
  /// fallback. Concurrent callers share the same in-flight load.
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
        AppLogger.warning(
          'Failed to load OpenRPC from asset and disk, using fallback',
          assetError,
          assetStack,
        );
        AppLogger.warning(
          'OpenRPC disk fallback also failed (cwd=${_cwdProvider()})',
          fileError,
          fileStack,
        );
      }
    } finally {
      _inFlight = null;
    }

    AppLogger.warning(
      'OpenRPC document unavailable; using minimal fallback. '
      'rpc.discover will return zero methods until the document can be loaded.',
    );

    final fallback = <String, dynamic>{
      'openrpc': '1.3.2',
      'info': <String, dynamic>{
        'title': 'Plug Agente Socket RPC',
        'version': ProtocolVersion.openRpcVersion,
      },
      'methods': <dynamic>[],
    };
    _cached = fallback;
    return fallback;
  }

  static Future<String> _defaultFileLoader(String filePath) {
    return File(filePath).readAsString();
  }

  static String _defaultCwdProvider() => Directory.current.path;
}
