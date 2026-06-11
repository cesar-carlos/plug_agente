import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

Object jsonDecodeUtf8PayloadInIsolate(Uint8List bytes) {
  final jsonString = utf8.decode(bytes);
  final decoded = jsonDecode(jsonString);
  if (decoded == null) {
    throw const FormatException('Top-level JSON payload must not be null');
  }
  return decoded as Object;
}

/// Top-level for [compute]: JSON-serializable values only.
Uint8List jsonUtf8EncodePayloadInIsolate(Object? data) {
  final raw = JsonUtf8Encoder().convert(data);
  return raw is Uint8List ? raw : Uint8List.fromList(raw);
}

Uint8List compressGzipInIsolate(Uint8List data) {
  final compressedBytes = GZipEncoder().encode(data);
  if (compressedBytes == null) {
    throw StateError('GZipEncoder returned null');
  }
  return Uint8List.fromList(compressedBytes);
}

Uint8List decompressGzipInIsolate(Uint8List compressed) {
  final decompressedBytes = GZipDecoder().decodeBytes(compressed);
  return Uint8List.fromList(decompressedBytes);
}
