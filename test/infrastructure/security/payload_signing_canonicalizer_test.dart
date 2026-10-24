import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/security/payload_signing_canonicalizer.dart';

void main() {
  group('PayloadSigningCanonicalizer', () {
    test('canonical utf-8 matches the historical string encoding', () {
      final value = <String, dynamic>{
        'z': 'plain',
        'a': <String, dynamic>{
          'm': 2,
          'b': true,
        },
        'rows': <Object?>[
          null,
          false,
          0,
          -2,
          1.0,
          1.5,
          '',
          'aspas " e barra \\ e\nlinha',
          'café',
          '😀',
          String.fromCharCode(0xD800),
        ],
        '10': 'depois',
        '2': 'antes',
      };

      final bytes = PayloadSigningCanonicalizer.canonicalJsonUtf8(value);

      expect(utf8.decode(bytes), _historicalCanonicalJson(value));
    });

    test('canonical utf-8 of uniform rows matches historical encoding', () {
      final value = <String, dynamic>{
        'rows': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'ana', 'id': 1, 'active': true},
          <String, dynamic>{'name': 'bia', 'id': 2, 'active': false},
        ],
      };

      expect(
        utf8.decode(PayloadSigningCanonicalizer.canonicalJsonUtf8(value)),
        _historicalCanonicalJson(value),
      );
    });

    test('a later nested row still matches historical encoding', () {
      final value = <String, dynamic>{
        'rows': <Object?>[
          <String, dynamic>{'id': 1},
          <String, dynamic>{
            'id': 2,
            'meta': <String, dynamic>{'z': 1, 'a': 2},
          },
        ],
      };

      expect(
        utf8.decode(PayloadSigningCanonicalizer.canonicalJsonUtf8(value)),
        _historicalCanonicalJson(value),
      );
    });

    test('frame payload text is signed as its own utf-8 bytes', () {
      const payload = 'não é base64!!!';

      expect(
        PayloadSigningCanonicalizer.payloadBytesForFrame(payload),
        utf8.encode(payload),
      );
    });
  });
}

String _historicalCanonicalJson(dynamic value) {
  final buffer = StringBuffer();
  _writeHistoricalCanonicalJson(buffer, value);
  return buffer.toString();
}

void _writeHistoricalCanonicalJson(StringBuffer buffer, dynamic value) {
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
      _writeHistoricalCanonicalJson(buffer, value[index]);
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
      _writeHistoricalCanonicalJson(buffer, entry.value);
    }
    buffer.write('}');
    return;
  }
  buffer.write(jsonEncode(value));
}
