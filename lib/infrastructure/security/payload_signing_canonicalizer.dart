import 'dart:convert';
import 'dart:typed_data';

import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';

final class PayloadSigningCanonicalizer {
  const PayloadSigningCanonicalizer._();

  static const List<String> legacyLogicalFields = <String>[
    'method',
    'id',
    'params',
    'result',
    'error',
  ];

  static Uint8List canonicalizeLogicalPayload(Map<String, dynamic> payload) {
    final signable = <String, dynamic>{};
    for (final field in legacyLogicalFields) {
      if (payload.containsKey(field)) {
        signable[field] = payload[field];
      }
    }
    return canonicalJsonUtf8(signable);
  }

  static Uint8List canonicalizeFrame(PayloadFrame frame) {
    final payloadBytes = payloadBytesForFrame(frame.payload);
    return canonicalJsonUtf8(<String, dynamic>{
      'schemaVersion': frame.schemaVersion,
      'enc': frame.enc,
      'cmp': frame.cmp,
      'contentType': frame.contentType,
      'originalSize': frame.originalSize,
      'compressedSize': frame.compressedSize,
      'traceId': frame.traceId,
      'requestId': frame.requestId,
      'payload': base64Encode(payloadBytes),
    });
  }

  static String canonicalFrameString(PayloadFrame frame) {
    return utf8.decode(canonicalizeFrame(frame));
  }

  static String canonicalLogicalPayloadString(Map<String, dynamic> payload) {
    return utf8.decode(canonicalizeLogicalPayload(payload));
  }

  static Uint8List payloadBytesForFrame(dynamic payload) {
    return switch (payload) {
      final Uint8List value => value,
      final ByteBuffer value => value.asUint8List(),
      final TypedData value => Uint8List.view(
        value.buffer,
        value.offsetInBytes,
        value.lengthInBytes,
      ),
      final List<int> value => Uint8List.fromList(value),
      final List<dynamic> value when value.every((item) => item is int) => Uint8List.fromList(value.cast<int>()),
      final String value => _tryDecodeBase64(value) ?? Uint8List.fromList(utf8.encode(value)),
      _ => Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    };
  }

  static Uint8List canonicalJsonUtf8(dynamic value) {
    return Uint8List.fromList(utf8.encode(_canonicalJson(value)));
  }

  static Uint8List? _tryDecodeBase64(String value) {
    try {
      return base64Decode(value);
    } on FormatException {
      return null;
    }
  }

  static String _canonicalJson(dynamic value) {
    final buffer = StringBuffer();
    _writeCanonicalJson(buffer, value);
    return buffer.toString();
  }

  static void _writeCanonicalJson(StringBuffer buffer, dynamic value) {
    if (value == null || value is bool || value is num || value is String) {
      buffer.write(jsonEncode(value));
      return;
    }
    if (value is List) {
      buffer.write('[');
      for (var index = 0; index < value.length; index++) {
        if (index > 0) {
          buffer.write(',');
        }
        _writeCanonicalJson(buffer, value[index]);
      }
      buffer.write(']');
      return;
    }
    if (value is Map) {
      final entries = value.entries.map((entry) => (key: entry.key.toString(), value: entry.value)).toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      buffer.write('{');
      for (var index = 0; index < entries.length; index++) {
        if (index > 0) {
          buffer.write(',');
        }
        final entry = entries[index];
        buffer
          ..write(jsonEncode(entry.key))
          ..write(':');
        _writeCanonicalJson(buffer, entry.value);
      }
      buffer.write('}');
      return;
    }
    buffer.write(jsonEncode(value));
  }
}
