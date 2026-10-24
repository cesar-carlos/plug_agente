import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_materialized_streaming_promotion_policy.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

void main() {
  const policy = SqlMaterializedStreamingPromotionPolicy();

  test('promotes a few wide rows based on real serialized volume', () {
    final rows = List<Map<String, dynamic>>.generate(
      3,
      (_) => <String, dynamic>{'payload': 'x' * 200000},
    );

    expect(
      policy.shouldPromote(
        rows: rows,
        limits: const TransportLimits(
          maxDecodedPayloadBytes: 4 * 1024 * 1024,
        ),
      ),
      isTrue,
    );
  });

  test('does not encode a row whose worst case still fits the threshold', () {
    final row = _ForEachProbe(<String, dynamic>{'id': 1, 'name': 'ana'});

    final promoted = policy.shouldPromote(
      rows: <Map<String, dynamic>>[row],
      limits: const TransportLimits(maxDecodedPayloadBytes: 1024 * 1024),
    );

    expect(promoted, isFalse);
    expect(row.forEachCalls, 0);
  });

  test('does not promote small materialized results', () {
    expect(
      policy.shouldPromote(
        rows: const <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
        ],
        limits: const TransportLimits(maxDecodedPayloadBytes: 1024 * 1024),
      ),
      isFalse,
    );
  });

  test('promotes an oversized row without encoding values after the wide cell', () {
    var encodedValues = 0;
    final rows = <Map<String, dynamic>>[
      <String, dynamic>{
        'payload': 'x' * ((512 * 1024) + 32),
        'later': _EncodeProbe(() => encodedValues++),
      },
    ];

    final promoted = policy.shouldPromote(
      rows: rows,
      limits: const TransportLimits(maxDecodedPayloadBytes: 4 * 1024 * 1024),
    );

    expect(promoted, isTrue);
    expect(encodedValues, 0);
  });

  test('uses the exact utf-8 size when the lower bound has not crossed the threshold', () {
    const row = <String, dynamic>{'id': 1, 'name': 'ana'};
    final perRow = JsonUtf8Encoder().convert(row).length + 1;
    final byteThreshold = perRow * 2;
    final limits = TransportLimits(maxDecodedPayloadBytes: byteThreshold * 4);

    expect(policy.shouldPromote(rows: const [row, row], limits: limits), isFalse);
    expect(
      policy.shouldPromote(rows: const [row, row, row], limits: limits),
      isTrue,
    );
  });
}

class _ForEachProbe extends MapBase<String, dynamic> {
  _ForEachProbe(Map<String, dynamic> source) : _source = Map<String, dynamic>.of(source);

  final Map<String, dynamic> _source;
  int forEachCalls = 0;

  @override
  Iterable<MapEntry<String, dynamic>> get entries => _source.entries;

  @override
  void forEach(void Function(String key, dynamic value) action) {
    forEachCalls++;
    _source.forEach(action);
  }

  @override
  dynamic operator [](Object? key) => _source[key];

  @override
  void operator []=(String key, dynamic value) => _source[key] = value;

  @override
  void clear() => _source.clear();

  @override
  Iterable<String> get keys => _source.keys;

  @override
  dynamic remove(Object? key) => _source.remove(key);
}

class _EncodeProbe {
  const _EncodeProbe(this.onEncode);

  final void Function() onEncode;

  Object toJson() {
    onEncode();
    return 'probe';
  }
}
