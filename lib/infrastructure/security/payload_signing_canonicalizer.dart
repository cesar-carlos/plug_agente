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
      final String value => _tryDecodeBase64(value) ?? utf8.encode(value),
      _ => utf8.encode(jsonEncode(payload)),
    };
  }

  static final JsonUtf8Encoder _jsonUtf8Encoder = JsonUtf8Encoder();

  static Uint8List canonicalJsonUtf8(dynamic value) {
    final raw = _jsonUtf8Encoder.convert(_canonicalJsonValue(value));
    if (raw is Uint8List) {
      return raw;
    }
    return Uint8List.fromList(raw);
  }

  /// Reuses plain lists and sorts only the containers whose key order is part
  /// of the canonical form. Uniform row maps share one sorted key order.
  static dynamic _canonicalJsonValue(dynamic value) {
    if (value is Map) {
      return _canonicalMap(value);
    }
    if (value is List) {
      return _canonicalList(value);
    }
    return value;
  }

  static Map<String, dynamic> _canonicalMap(Map<dynamic, dynamic> value) {
    final entries = value.entries.map((entry) => (key: entry.key.toString(), value: entry.value)).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final sorted = <String, dynamic>{};
    for (final entry in entries) {
      sorted[entry.key] = _canonicalJsonValue(entry.value);
    }
    return sorted;
  }

  static List<dynamic> _canonicalList(List<dynamic> values) {
    for (final value in values) {
      if (value is Map || value is List) {
        final plainRows = _sortedPlainRows(values);
        if (plainRows != null) {
          return plainRows;
        }
        return List<dynamic>.generate(
          values.length,
          (index) => _canonicalJsonValue(values[index]),
          growable: false,
        );
      }
    }
    return values;
  }

  /// Returns sorted copies when every item is a map with the same string keys
  /// and no nested container. A different shape returns null.
  static List<Map<String, dynamic>>? _sortedPlainRows(List<dynamic> rows) {
    if (rows.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final prototype = rows.first;
    if (prototype is! Map) {
      return null;
    }
    final keyOrder = <String>[];
    for (final key in prototype.keys) {
      if (key is! String) {
        return null;
      }
      final child = prototype[key];
      if (child is Map || child is List) {
        return null;
      }
      keyOrder.add(key);
    }
    keyOrder.sort();
    final sortedRows = List<Map<String, dynamic>>.filled(rows.length, const <String, dynamic>{});
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (row is! Map || row.length != keyOrder.length) {
        return null;
      }
      final sorted = <String, dynamic>{};
      for (final key in keyOrder) {
        if (!row.containsKey(key)) {
          return null;
        }
        final child = row[key];
        if (child is Map || child is List) {
          return null;
        }
        sorted[key] = child;
      }
      sortedRows[index] = sorted;
    }
    return sortedRows;
  }

  static Uint8List? _tryDecodeBase64(String value) {
    try {
      return base64Decode(value);
    } on FormatException {
      return null;
    }
  }
}
