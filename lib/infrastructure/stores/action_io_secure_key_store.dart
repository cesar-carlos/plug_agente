import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_cipher.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

/// The lock path belongs to the journal directory, never the operational vault directory.
final class ActionIoSecureKeyStore {
  ActionIoSecureKeyStore({required this.lockPath, FlutterSecureStorage? storage, String? keyName})
    : _storage = storage ?? const FlutterSecureStorage(),
      _keyName = keyName ?? storageKey;

  static const storageKey = 'agent_action_io_key_v1';
  final String lockPath;
  final FlutterSecureStorage _storage;
  final String _keyName;

  Future<Result<ActionIoPayloadCipher>> load({required bool journalIsEmpty}) async {
    RandomAccessFile? lock;
    var locked = false;
    Result<ActionIoPayloadCipher>? result;
    try {
      lock = await File(lockPath).open(mode: FileMode.append);
      await lock.lock();
      locked = true;
      var encoded = await _storage.read(key: _keyName);
      if (encoded == null) {
        if (!journalIsEmpty) throw const FormatException('Existing journal key is unavailable');
        final key = await AesGcm.with256bits().newSecretKey();
        encoded = jsonEncode({
          'version': 1,
          'key_id': const Uuid().v4(),
          'key': base64Encode(await key.extractBytes()),
        });
        await _storage.write(key: _keyName, value: encoded);
        if (await _storage.read(key: _keyName) != encoded) throw const FormatException('Key persistence unconfirmed');
      }
      final envelope = jsonDecode(encoded);
      if (envelope is! Map<String, dynamic> ||
          envelope['version'] != 1 ||
          envelope['key_id'] is! String ||
          (envelope['key_id'] as String).isEmpty ||
          envelope['key'] is! String) {
        throw const FormatException('Invalid I/O key envelope');
      }
      final bytes = base64Decode(envelope['key'] as String);
      if (bytes.length != 32 || base64Encode(bytes) != envelope['key']) {
        throw const FormatException('Invalid I/O key material');
      }
      result = Success(ActionIoPayloadCipher(keyId: envelope['key_id'] as String, key: SecretKey(bytes)));
    } on Exception catch (error) {
      result = Failure(_failure(error));
    } finally {
      if (lock != null) {
        try {
          if (locked) await lock.unlock();
        } on Exception catch (error) {
          if (result == null || result.isSuccess()) result = Failure(_failure(error));
        }
        try {
          await lock.close();
        } on Exception catch (error) {
          if (result == null || result.isSuccess()) result = Failure(_failure(error));
        }
      }
    }
    return result!;
  }

  ActionRuntimeFailure _failure(Object error) => ActionRuntimeFailure.withContext(
    message: 'The secure I/O journal key is unavailable. Restore the original key before continuing.',
    code: 'ACTION_IO_KEY_UNAVAILABLE',
    context: {'cause_type': error.runtimeType.toString(), 'retryable': false},
  );
}
