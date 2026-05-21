/// Updates a single key in the repo `.env` without printing secret values.
library;

import 'dart:io';

bool patchDotEnvKey({
  required String projectRoot,
  required String key,
  required String value,
  bool onlyIfEmpty = true,
}) {
  final envPath = '$projectRoot${Platform.pathSeparator}.env';
  final file = File(envPath);
  if (!file.existsSync()) {
    return false;
  }

  final lines = file.readAsLinesSync();
  var found = false;
  var changed = false;
  final updated = <String>[];

  for (final line in lines) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('#') && trimmed.startsWith('$key=')) {
      found = true;
      final current = _parseValue(trimmed.substring(key.length + 1));
      if (onlyIfEmpty && current.isNotEmpty) {
        updated.add(line);
        continue;
      }
      updated.add('$key=$value');
      changed = current != value;
      continue;
    }
    updated.add(line);
  }

  if (!found) {
    updated.add('$key=$value');
    changed = true;
  }

  if (changed) {
    file.writeAsStringSync('${updated.join('\n')}\n');
  }
  return changed;
}

String _parseValue(String raw) {
  final value = raw.trim();
  if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
    return value.substring(1, value.length - 1);
  }
  if (value.startsWith("'") && value.endsWith("'") && value.length >= 2) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

bool dotEnvKeyIsEmpty(String projectRoot, String key) {
  final file = File('$projectRoot${Platform.pathSeparator}.env');
  if (!file.existsSync()) {
    return true;
  }
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#') || !trimmed.startsWith('$key=')) {
      continue;
    }
    return _parseValue(trimmed.substring(key.length + 1)).isEmpty;
  }
  return true;
}
