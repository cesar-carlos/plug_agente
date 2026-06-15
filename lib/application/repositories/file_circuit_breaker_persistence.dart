// ignore_for_file: avoid_slow_async_io

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:plug_agente/application/repositories/i_circuit_breaker_persistence.dart';

/// File-backed circuit breaker persistence for degraded runtimes without settings store.
class FileCircuitBreakerPersistence implements ICircuitBreakerPersistence {
  FileCircuitBreakerPersistence({
    required this.fileName,
    String? basePath,
  }) : _basePath = basePath;

  final String fileName;
  final String? _basePath;

  int _failureCount = 0;
  DateTime? _cooldownUntil;
  bool _loaded = false;
  String? _cachedDir;

  @override
  int get failureCount {
    _ensureLoadedSync();
    return _failureCount;
  }

  @override
  DateTime? get cooldownUntil {
    _ensureLoadedSync();
    return _cooldownUntil;
  }

  @override
  Future<void> persistFailure({
    required int failureCount,
    DateTime? cooldownUntil,
  }) async {
    _failureCount = failureCount;
    _cooldownUntil = cooldownUntil;
    _loaded = true;
    await _writeState();
  }

  @override
  Future<void> clear() async {
    _failureCount = 0;
    _cooldownUntil = null;
    _loaded = true;
    final file = await _stateFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  void _ensureLoadedSync() {
    if (_loaded) {
      return;
    }
    final file = File(_syncStatePath());
    if (!file.existsSync()) {
      _loaded = true;
      return;
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        _failureCount = decoded['failure_count'] as int? ?? 0;
        final cooldownMs = decoded['cooldown_until_ms'] as int?;
        _cooldownUntil = cooldownMs == null || cooldownMs <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(cooldownMs);
      }
    } on Object {
      _failureCount = 0;
      _cooldownUntil = null;
    }
    _loaded = true;
  }

  String _syncStatePath() {
    final base = _basePath;
    if (base != null) {
      return p.join(base, fileName);
    }
    _cachedDir ??= Directory.systemTemp.path;
    return p.join(_cachedDir!, 'plug_agente', 'update_cb', fileName);
  }

  Future<File> _stateFile() async {
    final base = _basePath;
    final dirPath = base ?? p.join(await _resolveSupportDir(), 'plug_agente', 'update_cb');
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dirPath, fileName));
  }

  Future<String> _resolveSupportDir() async {
    _cachedDir ??= (await getApplicationSupportDirectory()).path;
    return _cachedDir!;
  }

  Future<void> _writeState() async {
    final file = await _stateFile();
    final payload = <String, Object?>{
      'failure_count': _failureCount,
      if (_cooldownUntil != null) 'cooldown_until_ms': _cooldownUntil!.millisecondsSinceEpoch,
    };
    await file.writeAsString(jsonEncode(payload));
  }
}
