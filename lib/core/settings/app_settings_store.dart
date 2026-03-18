import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';

abstract interface class IAppSettingsStore {
  bool? getBool(String key);
  int? getInt(String key);
  double? getDouble(String key);
  String? getString(String key);
  List<String>? getStringList(String key);
  Object? getValue(String key);
  Set<String> getKeys();
  bool containsKey(String key);

  Future<void> setBool(String key, bool value);
  Future<void> setInt(String key, int value);
  Future<void> setDouble(String key, double value);
  Future<void> setString(String key, String value);
  Future<void> setStringList(String key, List<String> value);
  Future<void> setValue(String key, Object value);
  Future<void> remove(String key);
  Future<void> setValues(Map<String, Object> values);
}

class GlobalAppSettingsStore implements IAppSettingsStore {
  GlobalAppSettingsStore({String? filePath}) : _filePath = filePath;

  String? _filePath;
  final Map<String, Object> _cache = <String, Object>{};
  Future<void> _writeQueue = Future<void>.value();

  Future<void> initialize() async {
    _filePath ??= await _resolveDefaultFilePath();

    final file = File(_requireFilePath());
    final parentDir = file.parent;
    if (!parentDir.existsSync()) {
      await parentDir.create(recursive: true);
    }

    if (!file.existsSync()) {
      return;
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Settings file is corrupted. Quarantining and continuing with defaults.',
        name: 'app_settings_store',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      await _quarantineCorruptedSettingsFile(file);
      _cache.clear();
      return;
    }

    if (decoded is! Map<String, dynamic>) {
      developer.log(
        'Settings file has invalid root type. Quarantining and continuing with defaults.',
        name: 'app_settings_store',
        level: 900,
      );
      await _quarantineCorruptedSettingsFile(file);
      _cache.clear();
      return;
    }

    _cache
      ..clear()
      ..addEntries(
        decoded.entries
            .where((entry) => _isSupportedValue(entry.value))
            .map((entry) => MapEntry(entry.key, _normalizeValue(entry.value)!)),
      );
  }

  @override
  bool? getBool(String key) {
    final value = _cache[key];
    return value is bool ? value : null;
  }

  @override
  int? getInt(String key) {
    final value = _cache[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  @override
  double? getDouble(String key) {
    final value = _cache[key];
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  @override
  String? getString(String key) {
    final value = _cache[key];
    return value is String ? value : null;
  }

  @override
  List<String>? getStringList(String key) {
    final value = _cache[key];
    if (value is List<String>) {
      return List<String>.from(value);
    }
    if (value is List) {
      if (value.every((item) => item is String)) {
        return List<String>.from(value.cast<String>());
      }
    }
    return null;
  }

  @override
  Object? getValue(String key) => _cache[key];

  @override
  Set<String> getKeys() => Set<String>.from(_cache.keys);

  @override
  bool containsKey(String key) => _cache.containsKey(key);

  @override
  Future<void> setBool(String key, bool value) => setValue(key, value);

  @override
  Future<void> setInt(String key, int value) => setValue(key, value);

  @override
  Future<void> setDouble(String key, double value) => setValue(key, value);

  @override
  Future<void> setString(String key, String value) => setValue(key, value);

  @override
  Future<void> setStringList(String key, List<String> value) =>
      setValue(key, List<String>.from(value));

  @override
  Future<void> setValue(String key, Object value) async {
    if (!_isSupportedValue(value)) {
      throw ArgumentError.value(value, 'value', 'Unsupported value type');
    }
    _cache[key] = _normalizeValue(value)!;
    await _persist();
  }

  @override
  Future<void> setValues(Map<String, Object> values) async {
    for (final entry in values.entries) {
      if (!_isSupportedValue(entry.value)) {
        throw ArgumentError.value(
          entry.value,
          entry.key,
          'Unsupported value type',
        );
      }
      _cache[entry.key] = _normalizeValue(entry.value)!;
    }
    await _persist();
  }

  @override
  Future<void> remove(String key) async {
    if (!_cache.containsKey(key)) {
      return;
    }
    _cache.remove(key);
    await _persist();
  }

  Future<int> importMissingEntries(Map<String, Object?> source) async {
    var migratedCount = 0;
    for (final entry in source.entries) {
      final key = _normalizeLegacyKey(entry.key);
      if (_cache.containsKey(key)) {
        continue;
      }

      final value = _normalizeValue(entry.value);
      if (value == null) {
        continue;
      }

      _cache[key] = value;
      migratedCount++;
    }

    if (migratedCount > 0) {
      await _persist();
    }

    return migratedCount;
  }

  Future<void> _quarantineCorruptedSettingsFile(File sourceFile) async {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final corruptedFile = File('${sourceFile.path}.corrupt.$timestamp');

    try {
      await sourceFile.rename(corruptedFile.path);
    } on FileSystemException catch (error, stackTrace) {
      developer.log(
        'Failed to quarantine corrupted settings file. Attempting delete.',
        name: 'app_settings_store',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      if (sourceFile.existsSync()) {
        await sourceFile.delete();
      }
    }
  }

  Future<void> _persist() {
    return _writeQueue = _writeQueue
        .catchError((Object e, StackTrace stackTrace) {
          developer.log(
            'Settings persist failed',
            name: 'app_settings_store',
            level: 900,
            error: e,
            stackTrace: stackTrace,
          );
        })
        .then((_) => _writeSnapshot());
  }

  Future<void> _writeSnapshot() async {
    final filePath = _requireFilePath();
    final file = File(filePath);
    final parentDir = file.parent;
    if (!parentDir.existsSync()) {
      await parentDir.create(recursive: true);
    }

    final sortedMap = SplayTreeMap<String, Object>.from(_cache);
    final tmpFile = File('$filePath.tmp');
    await tmpFile.writeAsString(jsonEncode(sortedMap));

    if (file.existsSync()) {
      await file.delete();
    }
    await tmpFile.rename(file.path);
  }

  Future<String> _resolveDefaultFilePath() async {
    final context = await GlobalStoragePathResolver.resolveContext();
    return context.settingsFilePath;
  }

  String _requireFilePath() {
    final filePath = _filePath;
    if (filePath != null && filePath.isNotEmpty) {
      return filePath;
    }
    throw StateError(
      'GlobalAppSettingsStore must be initialized before persistence.',
    );
  }

  static String _normalizeLegacyKey(String rawKey) {
    const flutterPrefix = 'flutter.';
    if (rawKey.startsWith(flutterPrefix)) {
      return rawKey.substring(flutterPrefix.length);
    }
    return rawKey;
  }

  static bool _isSupportedValue(Object? value) =>
      _normalizeValue(value) != null;

  static Object? _normalizeValue(Object? value) {
    if (value is bool || value is int || value is double || value is String) {
      return value;
    }
    if (value is num) {
      if (value == value.toInt()) {
        return value.toInt();
      }
      return value.toDouble();
    }
    if (value is List) {
      if (value.every((item) => item is String)) {
        return List<String>.from(value.cast<String>());
      }
    }
    return null;
  }
}

class InMemoryAppSettingsStore implements IAppSettingsStore {
  InMemoryAppSettingsStore([Map<String, Object>? initialValues]) {
    if (initialValues != null) {
      _data.addAll(initialValues);
    }
  }

  final Map<String, Object> _data = <String, Object>{};

  @override
  bool? getBool(String key) => _data[key] as bool?;

  @override
  double? getDouble(String key) {
    final value = _data[key];
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  @override
  int? getInt(String key) {
    final value = _data[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  @override
  Set<String> getKeys() => Set<String>.from(_data.keys);

  @override
  String? getString(String key) => _data[key] as String?;

  @override
  List<String>? getStringList(String key) {
    final value = _data[key];
    if (value is List<String>) {
      return List<String>.from(value);
    }
    return null;
  }

  @override
  Object? getValue(String key) => _data[key];

  @override
  bool containsKey(String key) => _data.containsKey(key);

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> setBool(String key, bool value) => setValue(key, value);

  @override
  Future<void> setDouble(String key, double value) => setValue(key, value);

  @override
  Future<void> setInt(String key, int value) => setValue(key, value);

  @override
  Future<void> setString(String key, String value) => setValue(key, value);

  @override
  Future<void> setStringList(String key, List<String> value) =>
      setValue(key, List<String>.from(value));

  @override
  Future<void> setValue(String key, Object value) async {
    _data[key] = value;
  }

  @override
  Future<void> setValues(Map<String, Object> values) async {
    _data.addAll(values);
  }
}
