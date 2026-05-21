/// Reads Plug Agente Windows secure storage (`flutter_secure_storage.dat`).
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

const String _encryptedFileName = 'flutter_secure_storage.dat';

/// Canonical path used by `flutter_secure_storage` when running `plug_agente.exe`.
String? plugAgenteSecureStorageFilePath() {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) {
    return null;
  }
  return p.join(appData, 'com.se7esistemas', 'plug_agente', _encryptedFileName);
}

/// Loads all key/value pairs from encrypted storage (empty map if missing).
Map<String, String> readPlugAgenteWindowsSecureStorage() {
  final path = plugAgenteSecureStorageFilePath();
  if (path == null) {
    return const <String, String>{};
  }
  final file = File(path);
  if (!file.existsSync()) {
    return const <String, String>{};
  }
  return _loadEncryptedJsonFile(file);
}

Map<String, String> _loadEncryptedJsonFile(File file) {
  final encryptedText = file.readAsBytesSync();
  final plainText = using((alloc) {
    final pEncryptedText = alloc<Uint8>(encryptedText.length);
    pEncryptedText.asTypedList(encryptedText.length).setAll(0, encryptedText);

    final encryptedTextBlob = alloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
    encryptedTextBlob.ref.cbData = encryptedText.length;
    encryptedTextBlob.ref.pbData = pEncryptedText;

    final plainTextBlob = alloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
    if (CryptUnprotectData(
          encryptedTextBlob,
          nullptr,
          nullptr,
          nullptr,
          nullptr,
          0,
          plainTextBlob,
        ) ==
        0) {
      throw WindowsException(GetLastError(), message: 'CryptUnprotectData failed');
    }

    if (plainTextBlob.ref.pbData.address == NULL) {
      throw WindowsException(ERROR_OUTOFMEMORY, message: 'CryptUnprotectData returned null');
    }

    try {
      return utf8.decoder.convert(
        plainTextBlob.ref.pbData.asTypedList(plainTextBlob.ref.cbData),
      );
    } finally {
      if (plainTextBlob.ref.pbData.address != NULL) {
        LocalFree(plainTextBlob.ref.pbData);
      }
    }
  });

  final decoded = jsonDecode(plainText);
  if (decoded is! Map) {
    throw const FormatException('Secure storage JSON is not an object');
  }

  return <String, String>{
    for (final entry in decoded.entries)
      if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
  };
}
