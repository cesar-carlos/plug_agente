import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/domain/errors/failures.dart' show ConfigurationFailure;
import 'package:plug_agente/domain/services/i_update_secrets_snapshot.dart';
import 'package:result_dart/result_dart.dart';

typedef UserSnapshotTransform = Future<String> Function(String input, bool encrypting);

/// Current-user DPAPI via the protected native client. Plaintext only crosses
/// anonymous stdin/stdout pipes and is never written to a file or diagnostics.
class WindowsUpdateSecretsSnapshot implements IUpdateSecretsSnapshot {
  WindowsUpdateSecretsSnapshot({FlutterSecureStorage? storage, UserSnapshotTransform? transform})
    : _storage = storage ?? const FlutterSecureStorage(),
      _transform = transform ?? _dpapi;

  final FlutterSecureStorage _storage;
  final UserSnapshotTransform _transform;

  @override
  Future<Result<String>> captureEncrypted() async {
    try {
      final all = await _storage.readAll();
      final entries = Map<String, String>.fromEntries(all.entries.where((entry) => isUpdateSecretKey(entry.key)));
      final plaintext = jsonEncode({'formatVersion': 1, 'namespaces': updateSecretNamespaces, 'entries': entries});
      return Success(await _transform(plaintext, true));
    } on Object {
      // Exceptions raised by secure storage may contain credential values.
      return Failure(
        ConfigurationFailure.withContext(
          message: 'Não foi possível proteger o snapshot de credenciais.',
          context: const {'reason': 'secrets_snapshot_unconfirmed'},
        ),
      );
    }
  }

  @override
  Future<Result<void>> restoreEncrypted(String encryptedBlob) async {
    try {
      final value = jsonDecode(await _transform(encryptedBlob, false)) as Map<String, dynamic>;
      if (value.length != 3 ||
          value['formatVersion'] is! int ||
          value['formatVersion'] != 1 ||
          jsonEncode(value['namespaces']) != jsonEncode(updateSecretNamespaces)) {
        throw const FormatException('Unsupported user snapshot');
      }
      final entries = Map<String, String>.from(value['entries'] as Map);
      if (entries.keys.any((key) => !isUpdateSecretKey(key))) throw const FormatException('Unknown secret namespace');
      final current = await _storage.readAll();
      for (final key in current.keys.where(isUpdateSecretKey).toList(growable: false)) {
        if (!entries.containsKey(key)) await _storage.delete(key: key);
      }
      for (final entry in entries.entries) {
        await _storage.write(key: entry.key, value: entry.value);
      }
      final confirmed = await _storage.readAll();
      final owned = Map<String, String>.fromEntries(confirmed.entries.where((entry) => isUpdateSecretKey(entry.key)));
      if (owned.length != entries.length || entries.entries.any((entry) => owned[entry.key] != entry.value)) {
        throw const FormatException('Secret restoration not confirmed');
      }
      return const Success(unit);
    } on Object {
      return Failure(
        ConfigurationFailure.withContext(
          message: 'A restauração de credenciais exige recuperação.',
          context: const {'reason': 'secrets_restore_unconfirmed'},
        ),
      );
    }
  }

  static Future<String> _dpapi(String input, bool encrypting) async {
    final client = p.join(
      Platform.environment['ProgramFiles'] ?? r'C:\Program Files',
      'PlugAgenteUpdater',
      'plug_update_client.exe',
    );
    if (utf8.encode(input).length > 512 * 1024) throw const FormatException('Snapshot too large');
    final process = await Process.start(client, [if (encrypting) '--protect-secrets' else '--unprotect-secrets']);
    Future<String> bounded(Stream<List<int>> source) async {
      final bytes = <int>[];
      await for (final chunk in source) {
        if (bytes.length + chunk.length > 1024 * 1024) throw const FormatException('Snapshot response too large');
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    }

    final outputs = Future.wait([bounded(process.stdout), bounded(process.stderr)]);
    try {
      process.stdin.add(utf8.encode(input));
      await process.stdin.close();
      final output = await outputs.timeout(const Duration(seconds: 30));
      if (await process.exitCode.timeout(const Duration(seconds: 5)) != 0) {
        throw const FormatException('User DPAPI failed');
      }
      if (!encrypting) return output.first;
      final response = jsonDecode(output.first) as Map<String, dynamic>;
      if (response['ok'] != true || response['blob'] is! String) throw const FormatException('User DPAPI failed');
      return response['blob'] as String;
    } finally {
      process.kill();
    }
  }
}
