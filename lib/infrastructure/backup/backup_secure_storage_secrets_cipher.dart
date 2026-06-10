import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:plug_agente/domain/backup/backup_secure_storage_secrets_constants.dart';

/// Encrypts/decrypts the secure-storage secrets payload for backup ZIP export.
abstract final class BackupSecureStorageSecretsCipher {
  static final AesGcm _algorithm = AesGcm.with256bits();

  static Future<Uint8List> encryptEntries(Map<String, String> entries) async {
    final payload = jsonEncode(<String, dynamic>{
      'version': BackupSecureStorageSecretsConstants.blobFormatVersion,
      'entries': entries,
    });
    final secretKey = SecretKey(_deriveKeyBytes());
    final secretBox = await _algorithm.encrypt(
      utf8.encode(payload),
      secretKey: secretKey,
    );
    final envelope = jsonEncode(<String, dynamic>{
      'v': BackupSecureStorageSecretsConstants.blobFormatVersion,
      'nonceB64': base64Encode(secretBox.nonce),
      'cipherTextB64': base64Encode(secretBox.cipherText),
      'macB64': base64Encode(secretBox.mac.bytes),
    });
    return Uint8List.fromList(utf8.encode(envelope));
  }

  static Future<Map<String, String>> decryptEntries(Uint8List envelopeBytes) async {
    final decoded = jsonDecode(utf8.decode(envelopeBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid secure storage secrets envelope');
    }

    final version = decoded['v'];
    if (version is! int || version != BackupSecureStorageSecretsConstants.blobFormatVersion) {
      throw FormatException('Unsupported secure storage secrets blob version: $version');
    }

    final nonceB64 = decoded['nonceB64'];
    final cipherTextB64 = decoded['cipherTextB64'];
    final macB64 = decoded['macB64'];
    if (nonceB64 is! String || cipherTextB64 is! String || macB64 is! String) {
      throw const FormatException('Malformed secure storage secrets envelope');
    }

    final secretKey = SecretKey(_deriveKeyBytes());
    final clearBytes = await _algorithm.decrypt(
      SecretBox(
        base64Decode(cipherTextB64),
        nonce: base64Decode(nonceB64),
        mac: Mac(base64Decode(macB64)),
      ),
      secretKey: secretKey,
    );

    final payload = jsonDecode(utf8.decode(clearBytes));
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Invalid secure storage secrets payload');
    }

    final payloadVersion = payload['version'];
    if (payloadVersion is! int || payloadVersion != BackupSecureStorageSecretsConstants.blobFormatVersion) {
      throw FormatException('Unsupported secure storage secrets payload version: $payloadVersion');
    }

    final rawEntries = payload['entries'];
    if (rawEntries is! Map) {
      throw const FormatException('Missing secure storage secrets entries');
    }

    final entries = <String, String>{};
    for (final entry in rawEntries.entries) {
      if (entry.key is! String || entry.value is! String) {
        continue;
      }
      final value = (entry.value as String).trim();
      if (value.isEmpty) {
        continue;
      }
      entries[entry.key as String] = value;
    }
    return entries;
  }

  static List<int> _deriveKeyBytes() {
    return sha256.convert(utf8.encode(BackupSecureStorageSecretsConstants.keyDerivationMaterial)).bytes;
  }
}
